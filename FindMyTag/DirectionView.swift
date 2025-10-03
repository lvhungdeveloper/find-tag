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
    
    private var currentAngle: Float = 0
    private var smoothedAngle: Float = 0
    private var isFirstUpdate = true
    
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
        
        // Setup radar rings (subtle background circles)
        for (index, ring) in radarRings.enumerated() {
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
            ring.lineWidth = 1.0
            layer.addSublayer(ring)
            
            // Stagger animation start times
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.6) {
                self.animateRing(ring, delay: Double(index) * 0.6)
            }
        }
        
        // Arrow image (pointing to tag) - add first
        arrowImageView.contentMode = .scaleAspectFit
        arrowImageView.tintColor = .systemGreen
        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.image = createArrowImage()
        addSubview(arrowImageView)
        
        // Center dot (represents iPhone) - add AFTER arrow so it's on top
        centerDot.backgroundColor = .systemBlue
        centerDot.layer.cornerRadius = 8
        centerDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerDot)
        
        // Distance label
        distanceLabel.textAlignment = .center
        distanceLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .bold)
        distanceLabel.textColor = .white
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(distanceLabel)
        
        // Name label (tag name)
        nameLabel.textAlignment = .center
        nameLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        nameLabel.textColor = .white.withAlphaComponent(0.8)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        // Hint label
        hintLabel.textAlignment = .center
        hintLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        hintLabel.textColor = .white.withAlphaComponent(0.6)
        hintLabel.text = "Move your iPhone to find"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        
        NSLayoutConstraint.activate([
            centerDot.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerDot.widthAnchor.constraint(equalToConstant: 16),
            centerDot.heightAnchor.constraint(equalToConstant: 16),
            
            arrowImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrowImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowImageView.widthAnchor.constraint(equalToConstant: 120),
            arrowImageView.heightAnchor.constraint(equalToConstant: 120),
            
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 80),
            
            distanceLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            distanceLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -120),
            
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: distanceLabel.bottomAnchor, constant: 12)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        // Update radar rings
        for (index, ring) in radarRings.enumerated() {
            let radius = (size / 2 - 40) * CGFloat(index + 1) / 3
            let path = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
            ring.path = path.cgPath
        }
    }
    
    private func createArrowImage() -> UIImage? {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            
            // Draw arrow pointing up (will be rotated later)
            let arrowPath = UIBezierPath()
            
            // Arrow head
            arrowPath.move(to: CGPoint(x: center.x, y: 20))
            arrowPath.addLine(to: CGPoint(x: center.x - 25, y: 50))
            arrowPath.addLine(to: CGPoint(x: center.x - 10, y: 50))
            
            // Arrow body
            arrowPath.addLine(to: CGPoint(x: center.x - 10, y: 100))
            arrowPath.addLine(to: CGPoint(x: center.x + 10, y: 100))
            arrowPath.addLine(to: CGPoint(x: center.x + 10, y: 50))
            
            // Complete arrow head
            arrowPath.addLine(to: CGPoint(x: center.x + 25, y: 50))
            arrowPath.close()
            
            UIColor.systemGreen.setFill()
            arrowPath.fill()
            
            // Add white border
            UIColor.white.setStroke()
            arrowPath.lineWidth = 3
            arrowPath.stroke()
        }
    }
    
    private func animateRing(_ ring: CAShapeLayer, delay: TimeInterval) {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.5
        scaleAnimation.toValue = 1.0
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.6
        opacityAnimation.toValue = 0.0
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = 2.5
        group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + delay
        
        ring.add(group, forKey: "pulse")
    }
    
    // MARK: - Public Methods
    func updateDirection(direction: simd_float3, distance: Float?) {
        // Calculate raw angle from direction vector
        // direction: x=right, y=up, z=backward
        // We want azimuth in XZ plane (horizontal direction)
        let rawAngle = atan2(direction.x, -direction.z)
        
        // Apply exponential smoothing filter (like Find My)
        // This reduces jitter while keeping responsiveness
        let smoothedAngle: Float
        
        if isFirstUpdate {
            // First update: set angle directly (no smoothing)
            smoothedAngle = rawAngle
            self.smoothedAngle = rawAngle
            isFirstUpdate = false
        } else {
            // Smooth the angle using exponential moving average
            // Alpha: 0.0 = very smooth but slow, 1.0 = no smoothing
            let alpha: Float = 0.4 // Sweet spot like Find My
            
            // Handle angle wrap-around (-π to π)
            var angleDiff = rawAngle - self.smoothedAngle
            
            // Normalize to [-π, π] (shortest path)
            if angleDiff > Float.pi {
                angleDiff -= 2 * Float.pi
            } else if angleDiff < -Float.pi {
                angleDiff += 2 * Float.pi
            }
            
            // Apply smoothing
            smoothedAngle = self.smoothedAngle + angleDiff * alpha
            self.smoothedAngle = smoothedAngle
        }
        
        // Haptic feedback when direction changes significantly
        if abs(rawAngle - currentAngle) > 0.8 {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        
        currentAngle = rawAngle
        
        // Apply rotation with smooth animation
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            self.arrowImageView.transform = CGAffineTransform(rotationAngle: CGFloat(smoothedAngle))
        }
        
        // Update distance
        if let distance = distance {
            distanceLabel.text = String(format: "%.1f m", distance)
        } else {
            distanceLabel.text = "-- m"
        }
    }
    
    func updateDistanceOnly(distance: Float?) {
        // Update distance without touching arrow rotation
        if let distance = distance {
            distanceLabel.text = String(format: "%.1f m", distance)
        } else {
            distanceLabel.text = "-- m"
        }
    }
    
    func showNoDirection() {
        UIView.animate(withDuration: 0.2) {
            self.arrowImageView.alpha = 0.25
            self.distanceLabel.alpha = 1.0  // Keep distance visible
            self.hintLabel.text = "Move around to find direction"
            self.hintLabel.textColor = .systemYellow.withAlphaComponent(0.8)
        }
    }
    
    func showHasDirection() {
        UIView.animate(withDuration: 0.2) {
            self.arrowImageView.alpha = 1.0
            self.distanceLabel.alpha = 1.0
            self.hintLabel.text = ""  // Hide hint when direction is available
            self.hintLabel.textColor = .white.withAlphaComponent(0.6)
        }
    }
    
    func setTagName(_ name: String) {
        nameLabel.text = "Finding \(name)"
    }
    
    func resetTracking() {
        // Reset tracking state when view appears
        isFirstUpdate = true
        currentAngle = 0
        smoothedAngle = 0
    }
}
