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
    private var currentAngle: Float = 0  // Góc hiện tại đang hiển thị (interpolated)
    private var targetAngle: Float = 0   // Góc mục tiêu (sau khi lọc)
    private var isFirstUpdate = true
    
    // Moving average filter - lưu nhiều raw samples để tính trung bình
    private var rawAngleHistory: [Float] = []
    private let historySize = 20  // Tăng từ 15 lên 20 để smooth hơn nữa
    
    // Weighted moving average weights - samples gần đây có trọng số cao hơn
    private let weights: [Float] = [0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.11, 0.12, 0.13, 0.12]  // Tổng = 1.0
    
    // CADisplayLink for smooth 60fps animation
    private var displayLink: CADisplayLink?
    
    // Exponential smoothing factor (double smoothing sau WMA)
    private let exponentialSmoothingFactor: Float = 0.15  // Thấp = smooth hơn
    
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
        
        // Start smooth animation loop
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
        // Smooth interpolation từ currentAngle đến targetAngle
        let angleDiff = shortestAngularDifference(from: currentAngle, to: targetAngle)
        
        // Exponential smoothing với damping
        let dampingFactor: Float = 0.08  // Thấp hơn = smooth hơn nhưng chậm hơn
        currentAngle = currentAngle + angleDiff * dampingFactor
        
        // Normalize angle
        currentAngle = normalizeAngle(currentAngle)
        
        // Apply rotation trực tiếp (không qua UIView.animate)
        arrowImageView.transform = CGAffineTransform(rotationAngle: CGFloat(currentAngle))
    }
    
    private func shortestAngularDifference(from: Float, to: Float) -> Float {
        var diff = to - from
        // Normalize to [-π, π] (shortest path)
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
        
        // Update gradient layer frame
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bounds
        }
    }
    
    
    // MARK: - Public Methods
    func updateDirection(direction: simd_float3, distance: Float?, deviceHeading: Float? = nil) {
        // ============================================================
        // STEP 1: VALIDATE & NORMALIZE DIRECTION VECTOR (RAW DATA)
        // ============================================================
        // Only use horizontal component (project to XZ plane)
        let horizontalDirection = simd_float3(direction.x, 0, direction.z)
        let magnitude = simd_length(horizontalDirection)
        
        // Giảm threshold để chấp nhận nhiều raw data hơn (từ 0.1 → 0.05)
        guard magnitude > 0.05 else {
            // Direction vector too weak - keep current angle
            return
        }
        
        // Normalize for consistent angle calculation
        let normalized = simd_normalize(horizontalDirection)
        
        // ============================================================
        // STEP 2: CALCULATE RAW ANGLE (không lọc)
        // ============================================================
        // UWB coordinate: x=right, y=up, z=backward
        // atan2(x, -z) gives angle relative to forward direction
        //   0° = forward, 90° = right, ±180° = backward, -90° = left
        let rawAngle = atan2(normalized.x, -normalized.z)
        
        // ============================================================
        // STEP 3: LƯU RAW ANGLE VÀO HISTORY
        // ============================================================
        rawAngleHistory.append(rawAngle)
        if rawAngleHistory.count > historySize {
            rawAngleHistory.removeFirst()
        }
        
        // ============================================================
        // STEP 4: ÁP DỤNG WEIGHTED MOVING AVERAGE (trung bình trượt có trọng số)
        // ============================================================
        let wmaAngle: Float
        
        if isFirstUpdate {
            // First reading: khởi tạo
            wmaAngle = rawAngle
            targetAngle = rawAngle
            currentAngle = rawAngle
            isFirstUpdate = false
        } else if rawAngleHistory.count < 3 {
            // Chưa đủ samples, dùng simple average
            wmaAngle = simpleMovingAverage(rawAngleHistory)
        } else {
            // Đủ samples, dùng weighted moving average
            // Samples gần đây có trọng số cao hơn
            wmaAngle = weightedMovingAverage(rawAngleHistory)
        }
        
        // ============================================================
        // STEP 5: DOUBLE SMOOTHING - Exponential smoothing sau WMA
        // ============================================================
        if !isFirstUpdate {
            // Tính angular difference
            let diff = shortestAngularDifference(from: targetAngle, to: wmaAngle)
            
            // Apply exponential moving average (layer thứ 2)
            targetAngle = normalizeAngle(targetAngle + diff * exponentialSmoothingFactor)
        }
        
        // ============================================================
        // STEP 6: UPDATE UI (CADisplayLink sẽ smooth interpolate đến targetAngle)
        // ============================================================
        let degrees = targetAngle * 180.0 / Float.pi
        
        // Check if arrow is pointing at dot (aligned with target)
        let isAligned = abs(targetAngle) < 0.17  // ~10 degrees tolerance
        
        if isAligned && abs(targetAngle - currentAngle) > 0.15 {
            // Just aligned → haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        
        // KHÔNG dùng UIView.animate - CADisplayLink sẽ handle rotation
        
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
    
    // ============================================================
    // HELPER: Simple Moving Average (SMA)
    // ============================================================
    private func simpleMovingAverage(_ angles: [Float]) -> Float {
        guard !angles.isEmpty else { return 0 }
        
        // Xử lý angle wrap-around (ví dụ: 179° và -179° cần average thành ±180°, không phải 0°)
        let reference = angles[0]
        var sum: Float = 0
        
        for angle in angles {
            var diff = angle - reference
            // Normalize difference to [-π, π]
            while diff > Float.pi { diff -= 2 * Float.pi }
            while diff < -Float.pi { diff += 2 * Float.pi }
            sum += diff
        }
        
        let averageDiff = sum / Float(angles.count)
        var result = reference + averageDiff
        
        // Normalize result to [-π, π]
        while result > Float.pi { result -= 2 * Float.pi }
        while result < -Float.pi { result += 2 * Float.pi }
        
        return result
    }
    
    // ============================================================
    // HELPER: Weighted Moving Average (WMA)
    // ============================================================
    private func weightedMovingAverage(_ angles: [Float]) -> Float {
        guard !angles.isEmpty else { return 0 }
        
        // Lấy N samples gần nhất (N = số lượng weights)
        let n = min(weights.count, angles.count)
        let recentAngles = Array(angles.suffix(n))
        let recentWeights = Array(weights.suffix(n))
        
        // Normalize weights nếu không dùng hết
        let weightSum = recentWeights.reduce(0, +)
        let normalizedWeights = recentWeights.map { $0 / weightSum }
        
        // Xử lý angle wrap-around
        let reference = recentAngles[0]
        var weightedSum: Float = 0
        
        for (angle, weight) in zip(recentAngles, normalizedWeights) {
            var diff = angle - reference
            // Normalize difference to [-π, π]
            while diff > Float.pi { diff -= 2 * Float.pi }
            while diff < -Float.pi { diff += 2 * Float.pi }
            weightedSum += diff * weight
        }
        
        var result = reference + weightedSum
        
        // Normalize result to [-π, π]
        while result > Float.pi { result -= 2 * Float.pi }
        while result < -Float.pi { result += 2 * Float.pi }
        
        return result
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
        targetAngle = 0
        rawAngleHistory.removeAll()
        isFirstUpdate = true
        centerDot.alpha = 1.0  // Reset dot opacity
        arrowImageView.transform = .identity  // Reset arrow rotation
    }
    
    deinit {
        // Clean up display link
        stopDisplayLink()
    }
}
