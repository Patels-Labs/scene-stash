import CoreMotion
import UIKit

/// Shares one device-motion stream between every visible tilt card.
final class Motion {
    static let shared = Motion()
    private let manager = CMMotionManager()
    private let cards = NSHashTable<TiltCardView>.weakObjects()
    private var reference: CMAttitude?
    private(set) var tilt = CGPoint.zero

    func attach(_ card: TiltCardView) {
        cards.add(card)
        start()
    }

    func detach(_ card: TiltCardView) {
        cards.remove(card)
        if cards.count == 0 { manager.stopDeviceMotionUpdates(); reference = nil }
    }

    private func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive, !UIAccessibility.isReduceMotionEnabled else { return }
        manager.deviceMotionUpdateInterval = 1 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude.copy() as? CMAttitude else { return }
            // Tilt is relative to how the phone was held when cards appeared, eased so it follows the hand slowly.
            if reference == nil { reference = attitude }
            if let reference { attitude.multiply(byInverseOf: reference) }
            let target = CGPoint(x: max(-1, min(1, attitude.roll / 0.5)), y: max(-1, min(1, attitude.pitch / 0.5)))
            tilt = CGPoint(x: tilt.x + (target.x - tilt.x) * 0.15, y: tilt.y + (target.y - tilt.y) * 0.15)
            for card in cards.allObjects { card.apply(tilt) }
        }
    }
}

/// A poster as a physical, glossy card: perspective tilt, moving glare, optional holographic foil.
final class TiltCardView: UIView {
    let imageView = UIImageView()
    var maxAngle: CGFloat = 0.14
    var foil = false { didSet { foilLayer.isHidden = !foil; setNeedsLayout() } }
    var cornerRadius: CGFloat = 14 { didSet { layoutSubviews() } }

    private let card = UIView()
    private let glare = CAGradientLayer()
    private let foilLayer = CAGradientLayer()
    private let edge = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 14)

        card.clipsToBounds = true
        card.layer.cornerCurve = .continuous
        card.backgroundColor = Theme.surfaceHigh
        addSubview(card)
        imageView.contentMode = .scaleAspectFill
        card.addSubview(imageView)

        foilLayer.colors = [
            UIColor(red: 1, green: 0.3, blue: 0.6, alpha: 1), UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
            UIColor(red: 0.3, green: 1, blue: 0.7, alpha: 1), UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1),
            UIColor(red: 0.8, green: 0.4, blue: 1, alpha: 1), UIColor(red: 1, green: 0.3, blue: 0.6, alpha: 1),
        ].map(\.cgColor)
        foilLayer.compositingFilter = "overlayBlendMode"
        foilLayer.opacity = 0.3
        foilLayer.isHidden = true
        card.layer.addSublayer(foilLayer)

        glare.type = .radial
        glare.colors = [UIColor(white: 1, alpha: 0.32).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        glare.compositingFilter = "screenBlendMode"
        card.layer.addSublayer(glare)

        // A hairline lit edge so the card reads as a printed object, not a flat rectangle.
        edge.borderWidth = 1
        edge.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        edge.cornerCurve = .continuous
        card.layer.addSublayer(edge)
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = bounds
        card.layer.cornerRadius = cornerRadius
        imageView.frame = card.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        foilLayer.frame = card.bounds.insetBy(dx: -bounds.width * 0.5, dy: -bounds.height * 0.5)
        glare.frame = card.bounds.insetBy(dx: -bounds.width * 0.6, dy: -bounds.height * 0.6)
        edge.frame = card.bounds
        edge.cornerRadius = cornerRadius
        CATransaction.commit()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        if foil, foilLayer.animation(forKey: "drift") == nil { shimmer() }
        apply(Motion.shared.tilt)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { Motion.shared.attach(self) } else { Motion.shared.detach(self) }
    }

    func apply(_ tilt: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var t = CATransform3DIdentity
        t.m34 = -1 / 900
        t = CATransform3DRotate(t, tilt.x * maxAngle, 0, 1, 0)
        t = CATransform3DRotate(t, -tilt.y * maxAngle, 1, 0, 0)
        card.layer.transform = t
        // Light sits up and to the left; the glare slides opposite the tilt.
        glare.startPoint = CGPoint(x: 0.35 - tilt.x * 0.25, y: 0.3 - tilt.y * 0.25)
        glare.endPoint = CGPoint(x: glare.startPoint.x + 0.35, y: glare.startPoint.y + 0.35)
        foilLayer.startPoint = CGPoint(x: 0.2 + tilt.x * 0.3, y: 0.0 + tilt.y * 0.3)
        foilLayer.endPoint = CGPoint(x: 0.8 + tilt.x * 0.3, y: 1.0 + tilt.y * 0.3)
        layer.shadowOffset = CGSize(width: -tilt.x * 10, height: 14 - tilt.y * 6)
        CATransaction.commit()
    }

    /// Foil drifts on its own too, so it reads as foil even when the phone is still (or on Mac).
    private func shimmer() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let drift = CABasicAnimation(keyPath: "transform.translation.x")
        drift.fromValue = -bounds.width * 0.25
        drift.toValue = bounds.width * 0.25
        drift.duration = 3.2
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        foilLayer.add(drift, forKey: "drift")
    }

    func setPoster(_ path: String?, size: ImageSize = .poster) {
        imageView.setImage(TMDB.imageURL(path, size))
    }
}
