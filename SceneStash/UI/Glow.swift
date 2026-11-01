import CoreImage
import UIKit

/// Ambient light from a poster: a heavily blurred copy washed across the top of the screen,
/// slowly breathing, like a projector spilling colour into a dark room.
final class GlowView: UIView {
    private let front = UIImageView()
    private let back = UIImageView()
    private let fade = CAGradientLayer()
    private var current: URL?
    var intensity: CGFloat = 0.75 { didSet { [front, back].forEach { $0.alpha = $0.image == nil ? 0 : intensity } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        for v in [back, front] {
            v.contentMode = .scaleAspectFill
            v.alpha = 0
            addSubview(v)
        }
        fade.colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.45, 1]
        layer.mask = fade
        NotificationCenter.default.addObserver(self, selector: #selector(breathe), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = bounds.insetBy(dx: -bounds.width * 0.25, dy: -bounds.height * 0.1)
        front.frame = r
        back.frame = r
        fade.frame = bounds
    }

    override func didMoveToWindow() { super.didMoveToWindow(); breathe() }

    /// Crossfades to the light of a new poster.
    func show(_ url: URL?) {
        guard url != current else { return }
        current = url
        guard let url else {
            UIView.animate(withDuration: 0.6) { self.front.alpha = 0 }
            return
        }
        Task {
            guard let image = await ImageLoader.shared.glow(for: url), current == url else { return }
            back.image = front.image
            back.alpha = front.alpha
            front.image = image
            front.alpha = 0
            UIView.animate(withDuration: 0.9, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.front.alpha = self.intensity
                self.back.alpha = 0
            }
        }
    }

    @objc private func breathe() {
        [front, back].forEach { $0.layer.removeAnimation(forKey: "breathe") }
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        for (i, v) in [front, back].enumerated() {
            let a = CABasicAnimation(keyPath: "transform")
            a.fromValue = CATransform3DIdentity
            a.toValue = CATransform3DRotate(CATransform3DMakeScale(1.18, 1.12, 1), i == 0 ? 0.08 : -0.08, 0, 0, 1)
            a.duration = 14
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            v.layer.add(a, forKey: "breathe")
        }
    }
}

extension ImageLoader {
    /// A tiny, heavily blurred, saturated version of an image; cheap to scale up full screen.
    func glow(for url: URL) async -> UIImage? {
        if let hit = glowCache.object(forKey: url as NSURL) { return hit }
        guard let image = await image(url), let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = 48 / max(input.extent.width, 1)
        let output = input
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 7])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6, kCIInputBrightnessKey: 0.02])
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 48 * input.extent.height / input.extent.width))
        guard let rendered = glowContext.createCGImage(output, from: output.extent) else { return nil }
        let result = UIImage(cgImage: rendered)
        glowCache.setObject(result, forKey: url as NSURL)
        return result
    }
}
