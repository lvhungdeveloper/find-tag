import UIKit
import simd

class DirectionView: UIView {
    
    // MARK: - UI Elements
    private let centerDot = UIView()
    private let arrowImageView = UIImageView()
    private let radarRings: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
    private let distanceLabel = UILabel()
    private let nameLabel = UILabel()
    private let hintLabel = UILabel()
    
    // Smoothing parameters
    private var currentAngle: Float = 0
    private var smoothedAngle: Float = 0
    private var isFirstUpdate = true
    
    // Median filter (for outlier rejection)
    private var angleHistory: [Float] = []
    private let historySize = 5
    
    // Low-pass filter (simple and effective)
    private let smoothingFactor: Float = 0.25  // Lower = smoother, Higher = more responsive
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        
        // Create gradient background (like Find My green)
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = UIScreen.main.bounds
        gradientLayer.colors = [
            UIColor(red: 0.4, green: 0.75, blue: 0.45, alpha: 1.0).cgColor,  // Light green
            UIColor(red: 0.3, green: 0.65, blue: 0.35, alpha: 1.0).cgColor   // Darker green
        ]
        gradientLayer.locations = [0.0, 1.0]
        layer.insertSublayer(gradientLayer, at: 0)
        
        // Arrow image (SF Symbol "arrow.up") - WHITE like Find My
        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.tintColor = .white
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Use SF Symbol "arrow.up"
        let config = UIImage.SymbolConfiguration(pointSize: 200, weight: .bold, scale: .large)
        arrowImageView.image = UIImage(systemName: "arrow.up", withConfiguration: config)
        arrowImageView.preferredSymbolConfiguration = config
        
        addSubview(arrowImageView)
        
        // Center dot (SF Symbol like arrow) - WHITE like Find My
        centerDot.translatesAutoresizingMaskIntoConstraints = false
        
        // Create dot image view with SF Symbol
        let dotImageView = UIImageView()
        dotImageView.contentMode = .scaleAspectFit
        dotImageView.tintColor = .white
        dotImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Use SF Symbol "circle.fill" for dot
        let dotConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold, scale: .large)
        dotImageView.image = UIImage(systemName: "circle.fill", withConfiguration: dotConfig)
        dotImageView.preferredSymbolConfiguration = dotConfig
        
        centerDot.addSubview(dotImageView)
        addSubview(centerDot)
        
        NSLayoutConstraint.activate([
            dotImageView.centerXAnchor.constraint(equalTo: centerDot.centerXAnchor),
            dotImageView.centerYAnchor.constraint(equalTo: centerDot.centerYAnchor),
            dotImageView.widthAnchor.constraint(equalToConstant: 32),
            dotImageView.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Distance label (large, white, bold)
        distanceLabel.textAlignment = .center
        distanceLabel.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        distanceLabel.textColor = .white
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(distanceLabel)
        
        // Hint label (direction text like "ahead", "behind")
        hintLabel.textAlignment = .center
        hintLabel.font = UIFont.systemFont(ofSize: 36, weight: .medium)
        hintLabel.textColor = .white
        hintLabel.text = "ahead"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        
        // Name label (tag name at top)
        nameLabel.textAlignment = .center
        nameLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            // Arrow at center (200x200)
            arrowImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrowImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            arrowImageView.widthAnchor.constraint(equalToConstant: 200),
            arrowImageView.heightAnchor.constraint(equalToConstant: 200),
            
            // Center dot - positioned AHEAD of arrow (represents tag location)
            centerDot.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerDot.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -200), // Above arrow
            centerDot.widthAnchor.constraint(equalToConstant: 32),
            centerDot.heightAnchor.constraint(equalToConstant: 32),
            
            // Name at top
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 60),
            
            // Distance at bottom (large) - moved higher to avoid cancel button
            distanceLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            distanceLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -150),
            
            // Direction text below distance
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: distanceLabel.bottomAnchor, constant: 8)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update gradient layer frame
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bounds
        }
    }
    
    
    // MARK: - Public Methods
    func updateDirection(direction: simd_float3, distance: Float?, deviceHeading: Float? = nil) {
        // ============================================================
        // STEP 1: VALIDATE & NORMALIZE DIRECTION VECTOR
        // ============================================================
        // Only use horizontal component (project to XZ plane)
        let horizontalDirection = simd_float3(direction.x, 0, direction.z)
        let magnitude = simd_length(horizontalDirection)
        
        // Reject invalid readings (too small magnitude = unreliable)
        guard magnitude > 0.1 else {
            // Direction vector too weak - keep current angle
            return
        }
        
        // Normalize for consistent angle calculation
        let normalized = simd_normalize(horizontalDirection)
        
        // ============================================================
        // STEP 2: CALCULATE ANGLE
        // ============================================================
        // UWB coordinate: x=right, y=up, z=backward
        // atan2(x, -z) gives angle relative to forward direction
        //   0° = forward, 90° = right, ±180° = backward, -90° = left
        let rawAngle = atan2(normalized.x, -normalized.z)
        
        // ============================================================
        // STEP 3: MEDIAN FILTER (reject outliers)
        // ============================================================
        angleHistory.append(rawAngle)
        if angleHistory.count > historySize {
            angleHistory.removeFirst()
        }
        
        // Use median to reject outliers
        let medianAngle: Float
        if angleHistory.count >= 3 {
            let sorted = angleHistory.sorted()
            medianAngle = sorted[sorted.count / 2]
        } else {
            medianAngle = rawAngle
        }
        
        // ============================================================
        // STEP 4: LOW-PASS FILTER (smooth but responsive)
        // ============================================================
        let finalAngle: Float
        
        if isFirstUpdate {
            // First reading: initialize
            smoothedAngle = medianAngle
            finalAngle = medianAngle
            isFirstUpdate = false
        } else {
            // Calculate shortest angular difference (handle wrap-around)
            var diff = medianAngle - smoothedAngle
            
            // Normalize to [-π, π] (shortest path)
            while diff > Float.pi { diff -= 2 * Float.pi }
            while diff < -Float.pi { diff += 2 * Float.pi }
            
            // Apply low-pass filter (exponential moving average)
            smoothedAngle = smoothedAngle + diff * smoothingFactor
            
            // Normalize result
            while smoothedAngle > Float.pi { smoothedAngle -= 2 * Float.pi }
            while smoothedAngle < -Float.pi { smoothedAngle += 2 * Float.pi }
            
            finalAngle = smoothedAngle
        }
        
        // Calculate degrees for direction text
        let degrees = finalAngle * 180.0 / Float.pi
        
        // Check if arrow is pointing at dot (aligned with target)
        let isAligned = abs(finalAngle) < 0.17  // ~10 degrees tolerance
        
        if isAligned && abs(finalAngle - currentAngle) > 0.15 {
            // Just aligned → haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        
        currentAngle = finalAngle
        
        // Apply rotation with animation
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            self.arrowImageView.transform = CGAffineTransform(rotationAngle: CGFloat(finalAngle))
        }
        
        // Fade dot when aligned (arrow pointing at it)
        UIView.animate(withDuration: 0.2) {
            self.centerDot.alpha = isAligned ? 0.3 : 1.0
        }
        
        // Update distance in METERS (show 0.0m if negative)
        if let distance = distance {
            let displayDistance = max(distance, 0.0)  // Clamp to 0 minimum
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
        
        // Update direction text based on angle
        let directionText = getDirectionText(degrees: degrees)
        hintLabel.text = directionText
    }
    
    func updateDistanceOnly(distance: Float?) {
        // Update distance without touching arrow rotation (show 0.0m if negative)
        if let distance = distance {
            let displayDistance = max(distance, 0.0)  // Clamp to 0 minimum
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
    }
    
    private func getDirectionText(degrees: Float) -> String {
        // Convert angle to compass direction like Find My
        // -180 to 180 degrees
        let normalized = degrees < 0 ? degrees + 360 : degrees
        
        switch normalized {
        case 337.5...360, 0..<22.5:
            return "ahead"
        case 22.5..<67.5:
            return "ahead right"
        case 67.5..<112.5:
            return "right"
        case 112.5..<157.5:
            return "behind right"
        case 157.5..<202.5:
            return "behind"
        case 202.5..<247.5:
            return "behind left"
        case 247.5..<292.5:
            return "left"
        case 292.5..<337.5:
            return "ahead left"
        default:
            return "ahead"
        }
    }
    
    func showNoDirection() {
        UIView.animate(withDuration: 0.2) {
            self.arrowImageView.alpha = 0.3
            self.distanceLabel.alpha = 1.0  // Keep distance visible
            self.hintLabel.text = "Move around"
            self.hintLabel.textColor = .white.withAlphaComponent(0.8)
        }
    }
    
    func showHasDirection() {
        UIView.animate(withDuration: 0.2) {
            self.arrowImageView.alpha = 1.0
            self.distanceLabel.alpha = 1.0
            // Direction text is set by updateDirection()
            self.hintLabel.textColor = .white
        }
    }
    
    func setTagName(_ name: String) {
        nameLabel.text = name
    }
    
    func resetTracking() {
        // Reset tracking state when view appears
        currentAngle = 0
        smoothedAngle = 0
        angleHistory.removeAll()
        isFirstUpdate = true
        centerDot.alpha = 1.0  // Reset dot opacity
    }
}
