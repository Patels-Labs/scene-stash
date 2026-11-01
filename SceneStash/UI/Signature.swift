import UIKit

// MARK: - Ticket button

/// The "Stash it" ticket. Untracked: tapping tears the stub off and flies it to the Stash tab.
/// Tracked: shows the status and opens a menu to change it.
final class TicketButton: UIButton {
    var onStash: (() -> Void)?
    private let shape = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let perforation: CAShapeLayer = TicketShape.perforation(x: 0, in: .zero)
    private let mainLabel = UILabel()
    private let stubIcon = UIImageView()
    private var stubWidth: CGFloat { 64 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(edge)
        layer.addSublayer(shape)
        layer.addSublayer(perforation)
        edge.fillColor = Theme.amberDeep.cgColor
        perforation.strokeColor = Theme.amberDeep.cgColor

        mainLabel.font = Theme.mono(.subheadline, weight: .bold)
        mainLabel.adjustsFontForContentSizeCategory = true
        mainLabel.textAlignment = .center
        mainLabel.adjustsFontSizeToFitWidth = true
        mainLabel.minimumScaleFactor = 0.7
        stubIcon.contentMode = .center
        stubIcon.preferredSymbolConfiguration = .init(pointSize: 18, weight: .bold)
        [mainLabel, stubIcon].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        addAction(UIAction { [weak self] _ in self?.onStash?() }, for: .primaryActionTriggered)
        setTint(Theme.amber)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTint(_ color: UIColor) {
        shape.fillColor = color.cgColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        let deep = UIColor(hue: h, saturation: min(s + 0.15, 1), brightness: b * 0.7, alpha: 1)
        edge.fillColor = deep.cgColor
        perforation.strokeColor = deep.cgColor
        mainLabel.textColor = Theme.ink
        stubIcon.tintColor = Theme.ink
    }

    /// nil = not in the stash yet.
    func configure(status: TrackStatus?, menu: UIMenu?) {
        if let status {
            mainLabel.text = "IN STASH · \(status.label.uppercased())"
            stubIcon.image = UIImage(systemName: status.symbol)
            accessibilityLabel = "In your stash: \(status.label)"
            accessibilityHint = "Change status"
        } else {
            mainLabel.text = "STASH IT"
            stubIcon.image = UIImage(systemName: "plus")
            accessibilityLabel = "Stash it"
            accessibilityHint = "Adds this to your watchlist"
        }
        self.menu = status == nil ? nil : menu
        showsMenuAsPrimaryAction = status != nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let face = bounds.inset(by: .init(top: 0, left: 0, bottom: 4, right: 0))
        let path = TicketShape.path(in: face, corner: 12, notch: 9).cgPath
        shape.path = path
        edge.path = path
        edge.frame = bounds.offsetBy(dx: 0, dy: 4)
        let px = face.maxX - stubWidth
        let p = UIBezierPath()
        p.move(to: CGPoint(x: px, y: face.minY + 8)); p.addLine(to: CGPoint(x: px, y: face.maxY - 8))
        perforation.path = p.cgPath
        mainLabel.frame = CGRect(x: 16, y: face.minY, width: px - 24, height: face.height)
        stubIcon.frame = CGRect(x: px, y: face.minY, width: stubWidth, height: face.height)
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(translationX: 0, y: 2).scaledBy(x: 0.98, y: 0.98) : .identity
            }
        }
    }

    /// Tears the stub along the perforation and flies it to `target` (window coordinates).
    func tear(to target: CGPoint, completion: @escaping () -> Void) {
        guard let window, !UIAccessibility.isReduceMotionEnabled,
              let stub = resizableSnapshotView(from: CGRect(x: bounds.maxX - stubWidth, y: 0, width: stubWidth, height: bounds.height), afterScreenUpdates: false, withCapInsets: .zero)
        else { Haptics.success(); completion(); return }

        stub.frame = convert(CGRect(x: bounds.maxX - stubWidth, y: 0, width: stubWidth, height: bounds.height), to: window)
        window.addSubview(stub)
        // Hide the real stub so the torn piece appears to come off this ticket.
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.frame = CGRect(x: 0, y: 0, width: bounds.width - stubWidth, height: bounds.height)
        layer.mask = mask
        Haptics.thunk()

        let start = stub.center
        let lift = CGPoint(x: start.x + 14, y: start.y - 30)
        let mid = CGPoint(x: (lift.x + target.x) / 2 + 40, y: min(lift.y, target.y) + (target.y - lift.y) * 0.25)
        UIView.animateKeyframes(withDuration: 0.9, delay: 0, options: [.calculationModeCubic]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                stub.center = lift
                stub.transform = CGAffineTransform(rotationAngle: 0.35)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.4) {
                stub.center = mid
                stub.transform = CGAffineTransform(rotationAngle: -0.6).scaledBy(x: 0.7, y: 0.7)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                stub.center = target
                stub.transform = CGAffineTransform(rotationAngle: -1.4).scaledBy(x: 0.2, y: 0.2)
                stub.alpha = 0.3
            }
        } completion: { _ in
            stub.removeFromSuperview()
            Haptics.soft()
            self.layer.mask = nil
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
                self.transform = .identity
            }
            completion()
        }
    }
}

// MARK: - Reel rating

/// Rating 1–10 on a scrolling strip of film frames with a detent per frame. 0 means unrated.
final class ReelRatingView: UIView, UIScrollViewDelegate {
    var onChange: ((Int) -> Void)?
    private(set) var value = 0
    var isInteracting: Bool { scroll.isTracking || scroll.isDecelerating }
    private let scroll = UIScrollView()
    private var frames: [UILabel] = []
    private let frameWidth: CGFloat = 54
    private let selection = UISelectionFeedbackGenerator()
    private let sprockets = CAShapeLayer()
    private var accent = Theme.amber

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.decelerationRate = .fast
        scroll.delegate = self
        addSubview(scroll)
        scroll.pin(to: self)
        sprockets.fillColor = UIColor(white: 1, alpha: 0.12).cgColor
        scroll.layer.addSublayer(sprockets)
        for i in 0...10 {
            let label = UILabel()
            label.text = i == 0 ? "–" : "\(i)"
            label.textAlignment = .center
            label.font = Theme.serif(.title2)
            label.textColor = Theme.paper
            label.layer.cornerRadius = 6
            label.layer.cornerCurve = .continuous
            label.clipsToBounds = true
            scroll.addSubview(label)
            frames.append(label)
        }
        heightAnchor.constraint(equalToConstant: 84).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "Your rating"
        // Fades the strip out at the edges, like film running off a spool.
        let fade = CAGradientLayer()
        fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        fade.locations = [0, 0.2, 0.8, 1]
        layer.mask = fade
    }
    required init?(coder: NSCoder) { fatalError() }

    func setAccent(_ color: UIColor) { accent = color; restyle() }

    func set(_ value: Int, animated: Bool) {
        self.value = value
        layoutIfNeeded()
        scroll.setContentOffset(CGPoint(x: CGFloat(value) * frameWidth - scroll.contentInset.left, y: 0), animated: animated)
        restyle()
        accessibilityValue = value == 0 ? "Not rated" : "\(value) out of 10"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.mask?.frame = bounds
        let side = bounds.width / 2 - frameWidth / 2
        scroll.contentInset = .init(top: 0, left: side, bottom: 0, right: side)
        scroll.contentSize = CGSize(width: frameWidth * CGFloat(frames.count), height: bounds.height)
        for (i, label) in frames.enumerated() {
            label.frame = CGRect(x: CGFloat(i) * frameWidth + 4, y: 16, width: frameWidth - 8, height: bounds.height - 32)
        }
        let holes = UIBezierPath()
        let span = frameWidth * CGFloat(frames.count) + bounds.width
        var x = -bounds.width / 2
        while x < span {
            holes.append(UIBezierPath(roundedRect: CGRect(x: x, y: 4, width: 8, height: 6), cornerRadius: 1.5))
            holes.append(UIBezierPath(roundedRect: CGRect(x: x, y: bounds.height - 10, width: 8, height: 6), cornerRadius: 1.5))
            x += frameWidth / 2
        }
        sprockets.path = holes.cgPath
        if !scroll.isDragging && !scroll.isDecelerating {
            scroll.contentOffset = CGPoint(x: CGFloat(value) * frameWidth - side, y: 0)
        }
        restyle()
    }

    private var centeredIndex: Int {
        let x = scroll.contentOffset.x + scroll.contentInset.left
        return min(max(Int((x / frameWidth).rounded()), 0), frames.count - 1)
    }

    private func restyle() {
        let center = scroll.contentOffset.x + bounds.width / 2
        for (i, label) in frames.enumerated() {
            let distance = abs(label.center.x - center) / frameWidth
            let scale = max(1 - distance * 0.12, 0.7)
            label.transform = CGAffineTransform(scaleX: scale, y: scale)
            let selected = i == centeredIndex
            label.backgroundColor = selected ? accent : UIColor(white: 1, alpha: 0.06)
            label.textColor = selected ? Theme.ink : Theme.paper.withAlphaComponent(max(1 - distance * 0.25, 0.3))
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let index = centeredIndex
        if index != value {
            value = index
            selection.selectionChanged()
        }
        restyle()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let side = scrollView.contentInset.left
        let index = ((targetContentOffset.pointee.x + side) / frameWidth).rounded()
        targetContentOffset.pointee.x = min(max(index, 0), CGFloat(frames.count - 1)) * frameWidth - side
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { commit() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { commit() } }

    private func commit() {
        accessibilityValue = value == 0 ? "Not rated" : "\(value) out of 10"
        onChange?(value)
    }

    override func accessibilityIncrement() { set(min(value + 1, 10), animated: true); commit() }
    override func accessibilityDecrement() { set(max(value - 1, 0), animated: true); commit() }
}

// MARK: - Punch button

/// Episode "watched" toggle that punches like a ticket clipper: the disc slams in and paper chips fly.
final class PunchButton: UIControl {
    private(set) var isPunched = false
    private let ring = CAShapeLayer()
    private let disc = CAShapeLayer()
    private let check = CAShapeLayer()
    var accent = Theme.amber { didSet { disc.fillColor = accent.cgColor } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        ring.fillColor = nil
        ring.strokeColor = UIColor(white: 1, alpha: 0.35).cgColor
        ring.lineWidth = 2
        ring.lineDashPattern = [3, 3]
        disc.fillColor = accent.cgColor
        check.strokeColor = Theme.ink.cgColor
        check.fillColor = nil
        check.lineWidth = 2.5
        check.lineCap = .round
        check.lineJoin = .round
        [ring, disc, check].forEach(layer.addSublayer)
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = CGRect(x: bounds.midX - 14, y: bounds.midY - 14, width: 28, height: 28)
        ring.path = UIBezierPath(ovalIn: r).cgPath
        [disc, check].forEach { $0.frame = bounds }
        disc.path = UIBezierPath(ovalIn: r).cgPath
        let c = UIBezierPath()
        c.move(to: CGPoint(x: r.minX + 8, y: r.midY + 0.5))
        c.addLine(to: CGPoint(x: r.midX - 1.5, y: r.maxY - 9))
        c.addLine(to: CGPoint(x: r.maxX - 7.5, y: r.minY + 9))
        check.path = c.cgPath
    }

    func set(_ punched: Bool, animated: Bool) {
        isPunched = punched
        accessibilityValue = punched ? "Watched" : "Not watched"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.opacity = punched ? 1 : 0
        check.strokeEnd = punched ? 1 : 0
        ring.opacity = punched ? 0 : 1
        CATransaction.commit()
        guard animated, punched, !UIAccessibility.isReduceMotionEnabled else { return }

        let slam = CASpringAnimation(keyPath: "transform.scale")
        slam.fromValue = 1.6
        slam.toValue = 1
        slam.damping = 9
        slam.initialVelocity = 4
        slam.duration = slam.settlingDuration
        disc.add(slam, forKey: "slam")
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.duration = 0.25
        draw.beginTime = CACurrentMediaTime() + 0.08
        draw.fillMode = .backwards
        check.add(draw, forKey: "draw")
        burst()
    }

    /// A few paper chips spray out of the punch.
    private func burst() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 20, height: 20)
        let chip = CAEmitterCell()
        chip.contents = UIGraphicsImageRenderer(size: CGSize(width: 5, height: 3)).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 5, height: 3))
        }.cgImage
        chip.color = accent.cgColor
        chip.birthRate = 160
        chip.lifetime = 0.55
        chip.velocity = 90
        chip.velocityRange = 40
        chip.emissionRange = .pi * 2
        chip.spin = 6
        chip.spinRange = 8
        chip.yAcceleration = 260
        chip.alphaSpeed = -1.8
        chip.scaleRange = 0.4
        emitter.emitterCells = [chip]
        layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { emitter.removeFromSuperlayer() }
    }
}

// MARK: - Marquee

/// Cinema-marquee frame with chasing bulbs around its edge.
final class MarqueeView: UIView {
    let content = UIStackView()
    private let dim = CAShapeLayer()
    private let lit = CAShapeLayer()
    private let panel = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.fillColor = Theme.inkRaised.cgColor
        panel.strokeColor = Theme.amberDeep.withAlphaComponent(0.6).cgColor
        panel.lineWidth = 1
        for (bulbs, color, gap) in [(dim, Theme.amber.withAlphaComponent(0.18), 14.0), (lit, Theme.amber, 42.0)] {
            bulbs.fillColor = nil
            bulbs.strokeColor = color.cgColor
            bulbs.lineWidth = 5
            bulbs.lineCap = .round
            bulbs.lineDashPattern = [0, NSNumber(value: gap)]
        }
        lit.shadowColor = Theme.amber.cgColor
        lit.shadowRadius = 4
        lit.shadowOpacity = 0.9
        lit.shadowOffset = .zero
        [panel, dim, lit].forEach(layer.addSublayer)

        content.axis = .horizontal
        content.distribution = .fillEqually
        content.spacing = 8
        addSubview(content)
        content.pin(to: self, inset: 22)
        NotificationCenter.default.addObserver(self, selector: #selector(chase), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerRadius: 18).cgPath
        let track = UIBezierPath(roundedRect: bounds.insetBy(dx: 9, dy: 9), cornerRadius: 12).cgPath
        dim.path = track
        lit.path = track
        chase()
    }

    override func didMoveToWindow() { super.didMoveToWindow(); chase() }

    @objc private func chase() {
        lit.removeAllAnimations()
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let run = CABasicAnimation(keyPath: "lineDashPhase")
        run.fromValue = 0
        run.toValue = -42
        run.duration = 0.9
        run.repeatCount = .infinity
        lit.add(run, forKey: "chase")
    }

    /// A stat column: big serif value over a mono caption.
    static func stat(_ value: String, _ caption: String) -> UIView {
        let v = UILabel()
        v.text = value
        v.font = Theme.serif(.title1)
        v.textColor = Theme.paper
        v.adjustsFontSizeToFitWidth = true
        v.minimumScaleFactor = 0.5
        v.textAlignment = .center
        let c = UILabel()
        c.text = caption.uppercased()
        c.font = Theme.mono(.caption2)
        c.textColor = Theme.amber
        c.textAlignment = .center
        c.adjustsFontSizeToFitWidth = true
        let stack = UIStackView(arrangedSubviews: [v, c])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(value) \(caption)"
        return stack
    }
}
