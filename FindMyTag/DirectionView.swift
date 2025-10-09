import UIKit
import simd

class DirectionView: UIView {
    
    // MARK: - UI Elements
    private let centerDot = UIView()
    private let arrowImageView = UIImageView()
    private let distanceLabel = UILabel()
    private let nameLabel = UILabel()
    private let hintLabel = UILabel()
    
    // Smoothing parameters
    private var currentAngle: Float = 0
    private var targetAngle: Float = 0
    private var isFirstUpdate = true
    
    // Simple moving average filter
    private var rawAngleHistory: [Float] = []
    private let historySize = 5
    
    // CADisplayLink for smooth 60fps animation
    private var displayLink: CADisplayLink?
    
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
        
        // Create gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = UIScreen.main.bounds
        gradientLayer.colors = [
            UIColor(red: 0.4, green: 0.75, blue: 0.45, alpha: 1.0).cgColor,
            UIColor(red: 0.3, green: 0.65, blue: 0.35, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        layer.insertSublayer(gradientLayer, at: 0)
        
        // Arrow image
        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.tintColor = .white
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let config = UIImage.SymbolConfiguration(pointSize: 200, weight: .bold, scale: .large)
        arrowImageView.image = UIImage(systemName: "arrow.up", withConfiguration: config)
        arrowImageView.preferredSymbolConfiguration = config
        
        addSubview(arrowImageView)
        
        // Center dot
        centerDot.translatesAutoresizingMaskIntoConstraints = false
        
        let dotImageView = UIImageView()
        dotImageView.contentMode = .scaleAspectFit
        dotImageView.tintColor = .white
        dotImageView.translatesAutoresizingMaskIntoConstraints = false
        
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
        
        // Distance label
        distanceLabel.textAlignment = .center
        distanceLabel.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        distanceLabel.textColor = .white
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(distanceLabel)
        
        // Hint label
        hintLabel.textAlignment = .center
        hintLabel.font = UIFont.systemFont(ofSize: 36, weight: .medium)
        hintLabel.textColor = .white
        hintLabel.text = "ahead"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        
        // Name label
        nameLabel.textAlignment = .center
        nameLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            arrowImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrowImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            arrowImageView.widthAnchor.constraint(equalToConstant: 200),
            arrowImageView.heightAnchor.constraint(equalToConstant: 200),
            
            centerDot.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerDot.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -200),
            centerDot.widthAnchor.constraint(equalToConstant: 32),
            centerDot.heightAnchor.constraint(equalToConstant: 32),
            
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 60),
            
            distanceLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            distanceLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -150),
            
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: distanceLabel.bottomAnchor, constant: 8)
        ])
        
        startDisplayLink()
    }
    
    // MARK: - Display Link Animation (60fps)
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplayLink))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateDisplayLink() {
        let angleDiff = shortestAngularDifference(from: currentAngle, to: targetAngle)
        
        let absDiff = abs(angleDiff)
        let dampingFactor: Float
        
        if absDiff > 0.5 {
            dampingFactor = 0.30
        } else if absDiff > 0.2 {
            dampingFactor = 0.22
        } else {
            dampingFactor = 0.15
        }
        
        currentAngle = currentAngle + angleDiff * dampingFactor
        currentAngle = normalizeAngle(currentAngle)
        
        arrowImageView.transform = CGAffineTransform(rotationAngle: CGFloat(currentAngle))
    }
    
    private func shortestAngularDifference(from: Float, to: Float) -> Float {
        var diff = to - from
        while diff > Float.pi { diff -= 2 * Float.pi }
        while diff < -Float.pi { diff += 2 * Float.pi }
        return diff
    }
    
    private func normalizeAngle(_ angle: Float) -> Float {
        var normalized = angle
        while normalized > Float.pi { normalized -= 2 * Float.pi }
        while normalized < -Float.pi { normalized += 2 * Float.pi }
        return normalized
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bounds
        }
    }
    
    // MARK: - Public Methods
    func updateDirection(direction: simd_float3, distance: Float?) {
        let magnitude = simd_length(direction)
        
        guard magnitude > 0.15 else {
            print("⚠️ Signal too weak: \(String(format: "%.3f", magnitude))")
            updateDistanceOnly(distance: distance)
            showNoDirection()
            return
        }
        
        let normalized = simd_normalize(direction)
        let isHighQualitySignal = magnitude > 0.6
        
        // Calculate azimuth (horizontal angle)
        let azimuth = atan2(normalized.x, -normalized.z)
        var rawAngle = azimuth
        
        // Calculate elevation for logging
        let horizontalMagnitude = sqrt(normalized.x * normalized.x + normalized.z * normalized.z)
        let elevation = atan2(normalized.y, horizontalMagnitude)
        
        let azimuthDeg = azimuth * 180.0 / Float.pi
        let elevationDeg = elevation * 180.0 / Float.pi
        let qualityEmoji = isHighQualitySignal ? "🟢" : "🟡"
        print("🎯 \(qualityEmoji) Azimuth: \(String(format: "%+.1f°", azimuthDeg)) | Elevation: \(String(format: "%+.1f°", elevationDeg)) | Mag: \(String(format: "%.2f", magnitude))")
        
        // Dead zone
        let deadZoneThreshold: Float = 5.0 * Float.pi / 180.0
        if abs(rawAngle) < deadZoneThreshold {
            rawAngle = 0
        }
        
        // Moving average
        rawAngleHistory.append(rawAngle)
        if rawAngleHistory.count > historySize {
            rawAngleHistory.removeFirst()
        }
        
        let smoothedAngle: Float
        
        if isFirstUpdate {
            smoothedAngle = rawAngle
            targetAngle = rawAngle
            currentAngle = rawAngle
            isFirstUpdate = false
        } else if rawAngleHistory.count < 2 {
            smoothedAngle = rawAngle
        } else {
            smoothedAngle = simpleMovingAverage(rawAngleHistory)
        }
        
        // Exponential smoothing
        if !isFirstUpdate {
            let diff = shortestAngularDifference(from: targetAngle, to: smoothedAngle)
            let adaptiveFactor: Float = isHighQualitySignal ? 0.60 : 0.35
            targetAngle = normalizeAngle(targetAngle + diff * adaptiveFactor)
        }
        
        // Update UI
        let degrees = targetAngle * 180.0 / Float.pi
        let isAligned = abs(targetAngle) < 0.17
        
        if isAligned && abs(targetAngle - currentAngle) > 0.15 {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        
        UIView.animate(withDuration: 0.2) {
            self.centerDot.alpha = isAligned ? 0.3 : 1.0
        }
        
        if let distance = distance {
            let displayDistance = max(distance, 0.0)
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
        
        let directionText = getDirectionText(degrees: degrees)
        hintLabel.text = directionText
    }
    
    private func updateDirectionFromHorizontalAngle(horizontalAngle: Float, distance: Float?) {
        var rawAngle = horizontalAngle
        
        print("📸 Horizontal Angle: \(String(format: "%+.1f°", rawAngle * 180 / Float.pi))")
        
        // Dead zone
        let deadZoneThreshold: Float = 5.0 * Float.pi / 180.0
        if abs(rawAngle) < deadZoneThreshold {
            rawAngle = 0
        }
        
        // Moving average
        rawAngleHistory.append(rawAngle)
        if rawAngleHistory.count > historySize {
            rawAngleHistory.removeFirst()
        }
        
        let smoothedAngle: Float
        
        if isFirstUpdate {
            smoothedAngle = rawAngle
            targetAngle = rawAngle
            currentAngle = rawAngle
            isFirstUpdate = false
        } else if rawAngleHistory.count < 2 {
            smoothedAngle = rawAngle
        } else {
            smoothedAngle = simpleMovingAverage(rawAngleHistory)
        }
        
        // Exponential smoothing
        if !isFirstUpdate {
            let diff = shortestAngularDifference(from: targetAngle, to: smoothedAngle)
            targetAngle = normalizeAngle(targetAngle + diff * 0.50)
        }
        
        // Update UI
        let degrees = targetAngle * 180.0 / Float.pi
        let isAligned = abs(targetAngle) < 0.17
        
        if isAligned && abs(targetAngle - currentAngle) > 0.15 {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        
        UIView.animate(withDuration: 0.2) {
            self.centerDot.alpha = isAligned ? 0.3 : 1.0
        }
        
        if let distance = distance {
            let displayDistance = max(distance, 0.0)
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
        
        let directionText = getDirectionText(degrees: degrees)
        hintLabel.text = directionText
        hintLabel.textColor = .white
    }
    
    private func simpleMovingAverage(_ angles: [Float]) -> Float {
        guard !angles.isEmpty else { return 0 }
        
        let reference = angles[0]
        var sum: Float = 0
        
        for angle in angles {
            var diff = angle - reference
            while diff > Float.pi { diff -= 2 * Float.pi }
            while diff < -Float.pi { diff += 2 * Float.pi }
            sum += diff
        }
        
        let averageDiff = sum / Float(angles.count)
        var result = reference + averageDiff
        
        while result > Float.pi { result -= 2 * Float.pi }
        while result < -Float.pi { result += 2 * Float.pi }
        
        return result
    }
    
    func updateDistanceOnly(distance: Float?) {
        if let distance = distance {
            let displayDistance = max(distance, 0.0)
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
    }
    
    // MARK: - Update with 2-tier fallback (direction → horizontalAngle)
    func updateWithOptionalDirection(direction: simd_float3?, horizontalAngle: Float?, distance: Float?) {
        if let direction = direction {
            // TIER 1: Use direction vector (most accurate)
            updateDirection(direction: direction, distance: distance)
            showHasDirection()
        } else if let horizontalAngle = horizontalAngle {
            // TIER 2: Use horizontalAngle from Camera Assistance
            updateDirectionFromHorizontalAngle(horizontalAngle: horizontalAngle, distance: distance)
            showHasDirection()
        } else {
            // No direction data - arrow fades
            updateDistanceOnly(distance: distance)
            showNoDirection()
        }
    }
    
    private func getDirectionText(degrees: Float) -> String {
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
            self.distanceLabel.alpha = 1.0
            self.hintLabel.text = "Move around"
            self.hintLabel.textColor = .white.withAlphaComponent(0.8)
        }
    }
    
    func showHasDirection() {
        UIView.animate(withDuration: 0.2) {
            self.arrowImageView.alpha = 1.0
            self.distanceLabel.alpha = 1.0
            self.hintLabel.textColor = .white
        }
    }
    
    func setTagName(_ name: String) {
        nameLabel.text = name
    }
    
    func resetTracking() {
        currentAngle = 0
        targetAngle = 0
        rawAngleHistory.removeAll()
        isFirstUpdate = true
        centerDot.alpha = 1.0
        arrowImageView.transform = .identity
        arrowImageView.alpha = 1.0
        print("🔄 Tracking reset")
    }
    
    deinit {
        stopDisplayLink()
    }
}
