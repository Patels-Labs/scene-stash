import UIKit

// MARK: - Film strip

/// A length of film standing in for a movie's runtime: frames fill with the poster's colour up to
/// where you are, with a glowing playhead. Interactive strips scrub in five-minute detents.
final class FilmStripView: UIControl {
    var value: Double = 0 { didSet { value = min(max(value, 0), 1); setNeedsDisplay(); updateAccessibility() } }
    var tint: UIColor = Theme.accent { didSet { setNeedsDisplay() } }
    /// Minutes the strip represents; drives haptic detents and VoiceOver.
    var runtime = 0 { didSet { updateAccessibility() } }
    var interactive = false { didSet { isUserInteractionEnabled = interactive; accessibilityTraits = interactive ? .adjustable : .none } }
    var frames = 12
    private let selection = UISelectionFeedbackGenerator()
    private var lastDetent = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let b = bounds
        UIColor(white: 0.1, alpha: 1).setFill()
        UIBezierPath(roundedRect: b, cornerRadius: min(6, b.height / 6)).fill()
        let sprocket = max(b.height * 0.14, 3)
        let band = CGRect(x: 0, y: sprocket * 1.7, width: b.width, height: b.height - sprocket * 3.4)
        let gap: CGFloat = 3
        let cell = (band.width - gap * CGFloat(frames - 1)) / CGFloat(frames)
        let filled = value * Double(frames)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        for i in 0..<frames {
            let r = CGRect(x: CGFloat(i) * (cell + gap), y: band.minY, width: cell, height: band.height)
            UIColor(white: i % 2 == 0 ? 0.2 : 0.17, alpha: 1).setFill()
            UIRectFill(r)
            let part = min(max(filled - Double(i), 0), 1)
            guard part > 0 else { continue }
            // Each frame a slightly different exposure, like real frames of the same scene.
            let shade = 0.62 + 0.38 * abs(sin(Double(i) * 1.7))
            UIColor(hue: hue, saturation: sat, brightness: bri * shade, alpha: 1).setFill()
            UIRectFill(CGRect(x: r.minX, y: r.minY, width: r.width * part, height: r.height))
        }
        UIColor.black.setFill()
        let pitch = sprocket * 2.4
        var x = pitch / 2
        while x < b.width {
            for y in [sprocket * 0.35, b.height - sprocket * 1.35] {
                UIBezierPath(roundedRect: CGRect(x: x - sprocket * 0.6, y: y, width: sprocket * 1.2, height: sprocket), cornerRadius: sprocket * 0.3).fill()
            }
            x += pitch
        }
        guard value > 0 else { return }
        let px = b.width * value
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setShadow(offset: .zero, blur: 8, color: UIColor.white.withAlphaComponent(0.9).cgColor)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: px - 1.5, y: 0, width: 3, height: b.height))
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        selection.prepare()
        scrub(touch)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { scrub(touch); return true }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { sendActions(for: .editingDidEnd) }

    private func scrub(_ touch: UITouch) {
        let raw = Double(touch.location(in: self).x / max(bounds.width, 1))
        let step = runtime > 0 ? 5 / Double(runtime) : 0.01
        value = (raw / step).rounded() * step
        let detent = Int((value / step).rounded())
        if detent != lastDetent { selection.selectionChanged(); lastDetent = detent }
        sendActions(for: .valueChanged)
    }

    private func updateAccessibility() {
        let minutes = Int(Double(runtime) * value)
        accessibilityValue = "\(DateText.runtime(minutes)) of \(DateText.runtime(runtime))"
    }
    override func accessibilityIncrement() { nudge(5) }
    override func accessibilityDecrement() { nudge(-5) }
    private func nudge(_ minutes: Int) {
        guard runtime > 0 else { return }
        value += Double(minutes) / Double(runtime)
        sendActions(for: .valueChanged)
        sendActions(for: .editingDidEnd)
    }
}

// MARK: - Punch card

/// A show's whole run as a transit punch card: one row of holes per season, punched for watched,
/// a glowing ring for the next one. Tapping a season row selects it.
final class PunchCardView: UIView {
    struct Row { let season: Int; let count: Int }
    var rows: [Row] = [] { didSet { setNeedsDisplay(); invalidateIntrinsicContentSize() } }
    var watched: Set<EpisodeKey> = [] { didSet { setNeedsDisplay() } }
    var upNext: EpisodeKey? { didSet { setNeedsDisplay() } }
    var aired: EpisodeKey? { didSet { setNeedsDisplay() } }
    var selected: Int? { didSet { setNeedsDisplay() } }
    var tint = Theme.accent { didSet { setNeedsDisplay() } }
    var onSelect: ((Int) -> Void)?

    static let labelWidth: CGFloat = 38, blockGap: CGFloat = 10
    /// Long-running shows get a finer card: twice the holes per row, no numbers.
    static func perRow(_ rows: [Row]) -> Int { rows.reduce(0) { $0 + $1.count } > 100 ? 20 : 10 }
    static func gap(_ rows: [Row]) -> CGFloat { perRow(rows) == 10 ? 6 : 4 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func hole(_ width: CGFloat, _ rows: [Row]) -> CGFloat {
        (width - labelWidth - gap(rows) * CGFloat(perRow(rows) - 1)) / CGFloat(perRow(rows))
    }
    private static func lines(_ count: Int, _ rows: [Row]) -> Int { max((count + perRow(rows) - 1) / perRow(rows), 1) }

    static func height(for width: CGFloat, rows: [Row]) -> CGFloat {
        let h = hole(width, rows), gap = gap(rows)
        return rows.reduce(0) { $0 + CGFloat(lines($1.count, rows)) * (h + gap) - gap } + blockGap * CGFloat(max(rows.count - 1, 0)) + 8
    }

    /// The frame of each season's block, top to bottom.
    private func blocks() -> [(Row, CGRect)] {
        let h = Self.hole(bounds.width, rows), gap = Self.gap(rows)
        var y: CGFloat = 4
        return rows.map { row in
            let height = CGFloat(Self.lines(row.count, rows)) * (h + gap) - gap
            defer { y += height + Self.blockGap }
            return (row, CGRect(x: 0, y: y, width: bounds.width, height: height))
        }
    }

    private func isAired(_ key: EpisodeKey) -> Bool {
        guard let aired else { return true }
        return key.season < aired.season || (key.season == aired.season && key.episode <= aired.episode)
    }

    override func draw(_ rect: CGRect) {
        let h = Self.hole(bounds.width, rows), gap = Self.gap(rows), perRow = Self.perRow(rows)
        let numberFont = UIFont.systemFont(ofSize: max(h * 0.36, 7), weight: .bold)
        for (row, block) in blocks() {
            let isSelected = row.season == selected
            if isSelected {
                tint.withAlphaComponent(0.12).setFill()
                UIBezierPath(roundedRect: block.insetBy(dx: -6, dy: -5), cornerRadius: 12).fill()
            }
            let label = NSAttributedString(string: "S\(row.season)", attributes: [
                .font: UIFont.systemFont(ofSize: min(h * 0.95, 24), weight: .black, width: .compressed),
                .foregroundColor: isSelected ? Theme.text : Theme.secondary,
            ])
            label.draw(at: CGPoint(x: 0, y: block.minY + (min(h, block.height) - label.size().height) / 2))
            for i in 0..<row.count {
                let key = EpisodeKey(season: row.season, episode: i + 1)
                let r = CGRect(x: Self.labelWidth + CGFloat(i % perRow) * (h + gap),
                               y: block.minY + CGFloat(i / perRow) * (h + gap), width: h, height: h)
                let circle = UIBezierPath(ovalIn: r)
                var ink = Theme.tertiary
                if watched.contains(key) {
                    // A punched hole: straight through to the dark behind the card.
                    UIColor.black.setFill(); circle.fill()
                    tint.withAlphaComponent(0.4).setStroke(); circle.lineWidth = 1; circle.stroke()
                    continue
                } else if key == upNext {
                    let ring = UIBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
                    ring.lineWidth = 2
                    tint.setStroke(); ring.stroke()
                    ink = tint
                } else if isAired(key) {
                    tint.withAlphaComponent(0.16).setFill(); circle.fill()
                } else {
                    let dashed = UIBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
                    dashed.lineWidth = 1
                    dashed.setLineDash([2, 2.5], count: 2, phase: 0)
                    Theme.hairline.setStroke(); dashed.stroke()
                    ink = UIColor(white: 1, alpha: 0.2)
                }
                guard h >= 18 else { continue }
                let n = NSAttributedString(string: "\(i + 1)", attributes: [.font: numberFont, .foregroundColor: ink])
                let s = n.size()
                n.draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
            }
        }
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        let y = g.location(in: self).y
        guard let hit = blocks().first(where: { $0.1.insetBy(dx: 0, dy: -Self.blockGap / 2).contains(CGPoint(x: 1, y: y)) }) else { return }
        Haptics.tap()
        onSelect?(hit.0.season)
    }

    override var accessibilityElements: [Any]? {
        get {
            blocks().map { row, frame in
                let e = UIAccessibilityElement(accessibilityContainer: self)
                let done = watched.filter { $0.season == row.season }.count
                e.accessibilityLabel = "Season \(row.season), \(done) of \(row.count) watched"
                e.accessibilityTraits = row.season == selected ? [.button, .selected] : .button
                e.accessibilityFrameInContainerSpace = frame
                return e
            }
        }
        set {}
    }
}

// MARK: - Tear-off stub

/// The perforated end of a programme card. Drag it off (or tap it) to tear it away.
final class StubView: UIView {
    var onTorn: (() -> Void)?
    let label = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let perforation = TicketShape.perforation()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.28)
        perforation.strokeColor = UIColor(white: 0, alpha: 0.55).cgColor
        layer.addSublayer(perforation)
        label.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        addSubview(label)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan))
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tear)))
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String) {
        label.setCaps(text, kern: 1.6)
        label.sizeToFit()
        accessibilityLabel = text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 0, y: bounds.height - 4))
        perforation.path = p.cgPath
        label.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: self)
        return abs(v.x) > abs(v.y)
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        let x = max(g.translation(in: self).x, 0)
        switch g.state {
        case .changed:
            transform = CGAffineTransform(translationX: x, y: x * 0.08).rotated(by: x / 600)
        case .ended where x > 44 || g.velocity(in: self).x > 600:
            tear()
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0) { self.transform = .identity }
        default: break
        }
    }

    @objc func tear() {
        Haptics.thunk()
        if let host = superview?.layer { PunchButton.chips(in: host, at: CGPoint(x: frame.minX, y: frame.midY), color: .white) }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.45, delay: 0, options: .curveEaseIn) {
            self.transform = CGAffineTransform(translationX: 160, y: 60).rotated(by: 0.6)
            self.alpha = 0
        } completion: { _ in
            self.onTorn?()
        }
    }

    func reset() {
        layer.removeAllAnimations()
        transform = .identity
        alpha = 1
    }

    override func accessibilityActivate() -> Bool { tear(); return true }
}
