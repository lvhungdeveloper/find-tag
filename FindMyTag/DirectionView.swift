import UIKit
import simd
import CoreLocation

class DirectionView: UIView {
    
    // MARK: - UI Elements
    private let centerDot = UIView()
    private let arrowImageView = UIImageView()
    private let radarRings: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
    private let distanceLabel = UILabel()
    private let nameLabel = UILabel()
    private let hintLabel = UILabel()
    
    // Smoothing parameters - BALANCED for smooth + responsive
    private var currentAngle: Float = 0  // Góc hiện tại đang hiển thị (interpolated)
    private var targetAngle: Float = 0   // Góc mục tiêu (sau khi lọc)
    private var isFirstUpdate = true
    
    // Simple moving average filter - Balance giữa smooth và responsive
    private var rawAngleHistory: [Float] = []
    private let historySize = 5  // Tăng lên 5 để ổn định hơn, giảm nhiễu
    
    // CADisplayLink for smooth 60fps animation
    private var displayLink: CADisplayLink?
    
    // Exponential smoothing factor - BALANCED
    private let exponentialSmoothingFactor: Float = 0.45  // Balance giữa nhanh và smooth
    
    // MARK: - Sensor Fusion - Cache last valid direction
    private var lastValidAngle: Float?            // Last valid azimuth (relative to device)
    private var lastValidDeviceHeading: Float?    // Device heading when we got last valid direction
    
    // Counter for consecutive nil directions
    private var consecutiveNilCount: Int = 0
    private let nilThreshold: Int = 3  // Dùng sensor fusion sau 3 lần nil liên tiếp
    
    // Location manager for device heading (compass)
    private let locationManager = CLLocationManager()
    private var currentDeviceHeading: Float = 0  // Current device heading from compass (radians)
    private var isHeadingReady = false  // Track if heading data is available
    
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
        
        // Start device heading tracking (compass) for sensor fusion
        startHeadingTracking()
    }
    
    // MARK: - Heading Tracking (Compass via CLLocationManager)
    private func startHeadingTracking() {
        locationManager.delegate = self
        
        // Check if heading is available
        guard CLLocationManager.headingAvailable() else {
            print("⚠️ Heading (compass) not available on this device")
            return
        }
        
        locationManager.headingFilter = 1  // Update every 1 degree change
        locationManager.startUpdatingHeading()
        print("🧭 Starting compass heading tracking...")
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
        
        // Adaptive damping - nhanh khi góc lớn, chậm khi góc nhỏ (tránh giật)
        let absDiff = abs(angleDiff)
        let dampingFactor: Float
        
        if absDiff > 0.5 {
            // Góc lớn (>28°) - xoay nhanh
            dampingFactor = 0.30
        } else if absDiff > 0.2 {
            // Góc trung bình (11-28°) - xoay vừa
            dampingFactor = 0.22
        } else {
            // Góc nhỏ (<11°) - xoay chậm để smooth, tránh giật
            dampingFactor = 0.15
        }
        
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
        // STEP 1: VALIDATE DIRECTION VECTOR (3D - with elevation)
        // ============================================================
        // Calculate FULL 3D magnitude (not just horizontal)
        let magnitude = simd_length(direction)
        
        // TĂNG threshold để lọc tín hiệu yếu/nhiễu (tránh góc nhảy lung tung)
        guard magnitude > 0.15 else {
            // Direction vector too weak - try to use cached direction
            tryUseCachedDirection(distance: distance)
            return
        }
        
        // Normalize 3D direction for consistent calculation
        let normalized = simd_normalize(direction)
        
        // Signal quality based on magnitude
        // Tín hiệu tốt → ít smoothing, responsive
        // Tín hiệu yếu → nhiều smoothing hơn, tránh nhiễu
        let isHighQualitySignal = magnitude > 0.6
        
        // ============================================================
        // STEP 2: EXTRACT AZIMUTH & ELEVATION (3D angles)
        // ============================================================
        // UWB coordinate: x=right, y=up, z=backward
        
        // AZIMUTH (góc ngang - horizontal angle): [-π, π]
        //   0° = forward, 90° = right, ±180° = backward, -90° = left
        let azimuth = atan2(normalized.x, -normalized.z)
        
        // ELEVATION (góc dọc - vertical angle): [-π/2, π/2]
        // Sử dụng asin(y) hoặc atan2(y, horizontal_magnitude)
        let horizontalMagnitude = sqrt(normalized.x * normalized.x + normalized.z * normalized.z)
        let elevation = atan2(normalized.y, horizontalMagnitude)
        
        // Debug log azimuth & elevation & signal quality
        let azimuthDeg = azimuth * 180.0 / Float.pi
        let elevationDeg = elevation * 180.0 / Float.pi
        let qualityEmoji = isHighQualitySignal ? "🟢" : "🟡"
        print("🎯 \(qualityEmoji) Azimuth: \(String(format: "%+.1f°", azimuthDeg)) | Elevation: \(String(format: "%+.1f°", elevationDeg)) | Mag: \(String(format: "%.2f", magnitude))")
        
        // ============================================================
        // STEP 3: 2D NAVIGATION - Chỉ dùng AZIMUTH (góc ngang)
        // ============================================================
        // ⚠️ QUAN TRỌNG: Vì hiển thị 2D arrow (không phụ thuộc độ cao iPhone),
        // ta CHỈ DÙNG AZIMUTH (góc ngang), BỎ QUA elevation để tránh sai khi iPhone nằm ngang
        //
        // UWB Direction Vector Convention:
        //   - direction.x > 0: Tag ở bên PHẢI
        //   - direction.x < 0: Tag ở bên TRÁI
        //   - direction.z < 0: Tag ở phía TRƯỚC
        //   - direction.z > 0: Tag ở phía SAU
        //
        // Azimuth = atan2(x, -z):
        //   - 0°: Tag ở phía TRƯỚC
        //   - +90°: Tag ở bên PHẢI
        //   - ±180°: Tag ở phía SAU
        //   - -90°: Tag ở bên TRÁI
        //
        // ⚠️ CRITICAL: Arrow rotation angle in UIKit:
        //   - 0 rad: Arrow points UP (default)
        //   - Positive rotation: Clockwise (right)
        //   - Negative rotation: Counter-clockwise (left)
        //
        // Để mũi tên chỉ đúng hướng về tag, dùng TRỰC TIẾP azimuth
        var rawAngle = azimuth
        
        // DEAD ZONE: Nếu góc quá nhỏ (< 5°), coi như thẳng (0°)
        // Tránh arrow rung khi tag gần như thẳng hàng
        let deadZoneThreshold: Float = 5.0 * Float.pi / 180.0  // 5 degrees
        if abs(rawAngle) < deadZoneThreshold {
            rawAngle = 0  // Snap to center
        }
        
        // ============================================================
        // STEP 4: LƯU RAW ANGLE VÀO HISTORY
        // ============================================================
        rawAngleHistory.append(rawAngle)
        if rawAngleHistory.count > historySize {
            rawAngleHistory.removeFirst()
        }
        
        // ============================================================
        // STEP 5: SIMPLE MOVING AVERAGE - Đơn giản và nhanh
        // ============================================================
        let smoothedAngle: Float
        
        if isFirstUpdate {
            // First reading: khởi tạo
            smoothedAngle = rawAngle
            targetAngle = rawAngle
            currentAngle = rawAngle
            isFirstUpdate = false
        } else if rawAngleHistory.count < 2 {
            // Chưa đủ samples, dùng raw angle trực tiếp
            smoothedAngle = rawAngle
        } else {
            // Dùng simple moving average (SMA) - nhanh và đơn giản
            smoothedAngle = simpleMovingAverage(rawAngleHistory)
        }
        
        // ============================================================
        // STEP 6: ADAPTIVE EXPONENTIAL SMOOTHING
        // ============================================================
        if !isFirstUpdate {
            // Tính angular difference
            let diff = shortestAngularDifference(from: targetAngle, to: smoothedAngle)
            
            // Adaptive smoothing factor dựa trên signal quality
            // Signal tốt → responsive (factor cao)
            // Signal yếu → smooth hơn (factor thấp) để tránh nhiễu
            let adaptiveFactor: Float = isHighQualitySignal ? 0.60 : 0.35
            
            // Apply exponential smoothing
            targetAngle = normalizeAngle(targetAngle + diff * adaptiveFactor)
        }
        
        // No caching - sensor fusion disabled
        
        // ============================================================
        // STEP 7: UPDATE UI (CADisplayLink sẽ smooth interpolate đến targetAngle)
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
    // HELPER: Check if cached direction exists
    // ============================================================
    private func isCacheValid() -> Bool {
        // Cache is valid if we have both angle and heading
        // NO expiry - cache lasts until we get new UWB signal!
        return lastValidAngle != nil && lastValidDeviceHeading != nil
    }
    
    private func invalidateCache() {
        lastValidAngle = nil
        lastValidDeviceHeading = nil
        print("❌ Cache invalidated")
    }
    
    // ============================================================
    // SENSOR FUSION: Use cached direction when UWB signal is lost
    // ============================================================
    private func tryUseCachedDirection(distance: Float?) {
        guard isCacheValid(),
              let cachedAngle = lastValidAngle,
              let cachedHeading = lastValidDeviceHeading else {
            // No cached data - show "no direction"
            updateDistanceOnly(distance: distance)
            showNoDirection()
            return
        }
        
        // ============================================================
        // CALCULATE ADJUSTED ANGLE using Sensor Fusion
        // ============================================================
        // Công thức: Tag ở absolute direction trong world space
        //   Tag absolute = cachedAngle + cachedHeading
        //   Current relative = Tag absolute - Current heading
        //                    = cachedAngle + (cachedHeading - currentHeading)
        //
        // Ví dụ: Tag ở phía trước (0°) khi heading=0°
        //        Quay lưng 180° → heading=180°
        //        → Relative = 0° + (0° - 180°) = -180° (tag ở phía sau) ✅
        
        let headingChange = currentDeviceHeading - cachedHeading
        let adjustedAngle = normalizeAngle(cachedAngle - headingChange)
        
        print("🔄 Sensor Fusion: cached=\(String(format: "%.1f°", cachedAngle * 180 / Float.pi)), headingΔ=\(String(format: "%.1f°", headingChange * 180 / Float.pi)), adjusted=\(String(format: "%.1f°", adjustedAngle * 180 / Float.pi))")
        
        // Update target angle smoothly
        let diff = shortestAngularDifference(from: targetAngle, to: adjustedAngle)
        targetAngle = normalizeAngle(targetAngle + diff * 0.70)
        
        // Update UI
        let degrees = adjustedAngle * 180.0 / Float.pi
        let directionText = getDirectionText(degrees: degrees)
        hintLabel.text = directionText
        
        // Update distance
        if let distance = distance {
            let displayDistance = max(distance, 0.0)
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
        
        // Keep arrow visible
        UIView.animate(withDuration: 0.3) {
            self.arrowImageView.alpha = 1.0
            self.hintLabel.textColor = .white
        }
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
    
    func updateDistanceOnly(distance: Float?) {
        // Update distance without touching arrow rotation (show 0.0m if negative)
        if let distance = distance {
            let displayDistance = max(distance, 0.0)  // Clamp to 0 minimum
            distanceLabel.text = String(format: "%.1f m", displayDistance)
        } else {
            distanceLabel.text = "-- m"
        }
    }
    
    // MARK: - Update with optional direction/horizontalAngle (SIMPLIFIED - NO SENSOR FUSION)
    func updateWithOptionalDirection(direction: simd_float3?, horizontalAngle: Float?, distance: Float?) {
        if let direction = direction {
            // Has direction vector - use it
            updateDirection(direction: direction, distance: distance)
            showHasDirection()
            print("✅ Using direction vector")
        } else if let horizontalAngle = horizontalAngle {
            // No direction, but has horizontalAngle - use it
            updateDirectionFromHorizontalAngle(horizontalAngle: horizontalAngle, distance: distance)
            showHasDirection()
            print("🟢 Using horizontalAngle (RARE!)")
        } else {
            // No data at all - show "no direction"
            updateDistanceOnly(distance: distance)
            showNoDirection()
            print("🔴 No direction data - arrow faded")
        }
    }
    
    // MARK: - Update using horizontalAngle only (TIER 2)
    private func updateDirectionFromHorizontalAngle(horizontalAngle: Float, distance: Float?) {
        var rawAngle = horizontalAngle
        
        print("🎯 Horizontal Angle: \(String(format: "%+.1f°", rawAngle * 180 / Float.pi))")
        
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
        
        // No caching - sensor fusion disabled
        
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
        centerDot.alpha = 1.0
        arrowImageView.transform = .identity
        arrowImageView.alpha = 1.0
        print("🔄 Tracking reset")
    }
    
    deinit {
        // Clean up display link and location manager
        stopDisplayLink()
        locationManager.stopUpdatingHeading()
    }
}

// MARK: - CLLocationManagerDelegate
extension DirectionView: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Convert compass heading (0-360°, clockwise from North) to radians
        // Note: 0° = North, 90° = East, 180° = South, 270° = West
        let headingDegrees = Float(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
        currentDeviceHeading = headingDegrees * Float.pi / 180.0  // Convert to radians
        
        if !isHeadingReady {
            isHeadingReady = true
            print("✅ Compass heading ready, initial: \(String(format: "%.1f°", headingDegrees))")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ Location manager error: \(error.localizedDescription)")
    }
}
