import UIKit

/// Three beats: the projector intro, picking titles you've loved (drifting physics posters), and your streaming services.
final class OnboardingViewController: UIViewController {
    private var beat = 0
    private let stage = UIView()
    private let button = UIButton(configuration: .filled())
    private var picked: [Title] = []
    private var current: UIView?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(stage)
        stage.pin(to: view)

        button.configuration?.baseBackgroundColor = Theme.amber
        button.configuration?.baseForegroundColor = Theme.ink
        button.configuration?.cornerStyle = .capsule
        button.configuration?.buttonSize = .large
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs; a.font = Theme.mono(.headline, weight: .bold); return a
        }
        button.addAction(UIAction { [weak self] _ in self?.advance() }, for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
        show(LightsDownView(), title: "LIGHTS DOWN", animated: false)
        button.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard beat == 0, let intro = current as? LightsDownView else { return }
        intro.play()
        UIView.animate(withDuration: 0.6, delay: UIAccessibility.isReduceMotionEnabled ? 0 : 2.6) { self.button.alpha = 1 }
    }

    private func advance() {
        Haptics.tap()
        beat += 1
        switch beat {
        case 1:
            let picker = PickerView()
            picker.onChange = { [weak self] picked in
                self?.picked = picked
                self?.button.configuration?.title = picked.isEmpty ? "SKIP" : "KEEP \(picked.count)"
            }
            show(picker, title: "SKIP", animated: true)
        case 2:
            show(ServicesBeatView(), title: "START WATCHING", animated: true)
        default:
            finish()
        }
    }

    /// Film-advance transition: the old frame slides up and out as the next one rises in.
    private func show(_ next: UIView, title: String, animated: Bool) {
        button.configuration?.title = title
        stage.addSubview(next)
        next.pin(to: stage)
        guard animated, let old = current else { current = next; return }
        current = next
        stage.layoutIfNeeded()
        let reduce = UIAccessibility.isReduceMotionEnabled
        next.transform = reduce ? .identity : CGAffineTransform(translationX: 0, y: view.bounds.height * 0.6)
        next.alpha = 0
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            old.transform = reduce ? .identity : CGAffineTransform(translationX: 0, y: -self.view.bounds.height * 0.4)
            old.alpha = 0
            next.transform = .identity
            next.alpha = 1
        } completion: { _ in
            old.removeFromSuperview()
        }
    }

    private func finish() {
        for title in picked { Store.shared.track(title, status: .seen) }
        Prefs.onboarded = true
        Haptics.success()
        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseIn) {
            self.view.alpha = 0
            if !UIAccessibility.isReduceMotionEnabled { self.view.transform = CGAffineTransform(scaleX: 1.08, y: 1.08) }
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }
}

// MARK: - Beat 1: lights down

private final class LightsDownView: UIView {
    private let glow = CAGradientLayer()
    private let beam = CAGradientLayer()
    private let beamMask = CAShapeLayer()
    private let ticket = CAShapeLayer()
    private let glyphs = CAShapeLayer()
    private let wordmark = UILabel()
    private let tagline = UILabel()
    private var apex: CGPoint { CGPoint(x: bounds.width * 0.14, y: bounds.height * 0.1) }
    private var ticketCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.height * 0.4) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        glow.type = .radial
        glow.colors = [UIColor(red: 1, green: 0.92, blue: 0.78, alpha: 1).cgColor, Theme.amber.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor]
        glow.locations = [0, 0.18, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = 0
        beam.colors = [Theme.amber.withAlphaComponent(0.45).cgColor, Theme.amber.withAlphaComponent(0.05).cgColor]
        beam.mask = beamMask
        beam.opacity = 0
        ticket.fillColor = UIColor.clear.cgColor
        ticket.strokeColor = Theme.amber.cgColor
        ticket.lineWidth = 2.5
        ticket.strokeEnd = 0
        ticket.shadowColor = Theme.amber.cgColor
        ticket.shadowRadius = 20
        ticket.shadowOpacity = 0
        ticket.shadowOffset = .zero
        glyphs.fillColor = UIColor.black.cgColor
        glyphs.opacity = 0
        [beam, glow, ticket, glyphs].forEach(layer.addSublayer)

        wordmark.text = "Scene Stash"
        wordmark.font = Theme.serif(.largeTitle, weight: .black).withSize(46)
        wordmark.textColor = Theme.paper
        wordmark.textAlignment = .center
        wordmark.adjustsFontSizeToFitWidth = true
        wordmark.accessibilityTraits = .header
        tagline.text = "Every film, every episode —\nkept like ticket stubs."
        tagline.font = Theme.serif(.title3, weight: .regular)
        tagline.textColor = Theme.paper.withAlphaComponent(0.65)
        tagline.numberOfLines = 0
        tagline.textAlignment = .center
        tagline.adjustsFontForContentSizeCategory = true
        let words = UIStackView(arrangedSubviews: [wordmark, tagline])
        words.axis = .vertical
        words.spacing = 10
        addSubview(words)
        words.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            words.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            words.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            words.topAnchor.constraint(equalTo: centerYAnchor, constant: 70),
        ])
        [wordmark, tagline].forEach { $0.alpha = 0 }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGFloat = 220
        glow.frame = CGRect(x: apex.x - size / 2, y: apex.y - size / 2, width: size, height: size)
        beam.frame = bounds
        beam.startPoint = CGPoint(x: apex.x / bounds.width, y: apex.y / bounds.height)
        beam.endPoint = CGPoint(x: 1, y: 1)
        beamMask.path = beamPath(spread: 0.32).cgPath

        let w = min(bounds.width * 0.72, 300), h = w * 0.54
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let transform = CGAffineTransform(translationX: ticketCenter.x, y: ticketCenter.y).rotated(by: -.pi / 16)
        let outline = TicketShape.path(in: rect, corner: w * 0.066, notch: w * 0.083)
        outline.apply(transform)
        ticket.path = outline.cgPath

        // Play glyph, perforation dots and punch hole, matching the app icon.
        let g = UIBezierPath()
        let cx = rect.minX + w * 0.33
        g.move(to: CGPoint(x: cx - w * 0.07, y: -h * 0.19))
        g.addLine(to: CGPoint(x: cx + w * 0.11, y: 0))
        g.addLine(to: CGPoint(x: cx - w * 0.07, y: h * 0.19))
        g.close()
        g.append(UIBezierPath(arcCenter: CGPoint(x: rect.maxX - w * 0.15, y: 0), radius: w * 0.063, startAngle: 0, endAngle: .pi * 2, clockwise: true))
        var y = rect.minY + h * 0.1
        while y < rect.maxY - h * 0.08 {
            g.append(UIBezierPath(arcCenter: CGPoint(x: rect.maxX - w * 0.3, y: y), radius: w * 0.013, startAngle: 0, endAngle: .pi * 2, clockwise: true))
            y += h * 0.095
        }
        g.apply(transform)
        glyphs.path = g.cgPath
    }

    private func beamPath(spread: CGFloat) -> UIBezierPath {
        let dir = atan2(ticketCenter.y - apex.y, ticketCenter.x - apex.x)
        let far = max(bounds.width, bounds.height) * 1.6
        let p = UIBezierPath()
        p.move(to: apex)
        p.addLine(to: CGPoint(x: apex.x + far * cos(dir - spread), y: apex.y + far * sin(dir - spread)))
        p.addLine(to: CGPoint(x: apex.x + far * cos(dir + spread), y: apex.y + far * sin(dir + spread)))
        p.close()
        return p
    }

    func play() {
        layoutIfNeeded()
        if UIAccessibility.isReduceMotionEnabled {
            glow.opacity = 1; beam.opacity = 1; ticket.strokeEnd = 1
            ticket.fillColor = Theme.amber.cgColor; glyphs.opacity = 1
            wordmark.alpha = 1; tagline.alpha = 1
            return
        }
        let now = CACurrentMediaTime()
        func animate(_ layer: CALayer, _ key: String, from: Any?, to: Any, at delay: CFTimeInterval, duration: CFTimeInterval, timing: CAMediaTimingFunctionName = .easeInEaseOut) {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.beginTime = now + delay
            a.duration = duration
            a.fillMode = .backwards
            a.timingFunction = CAMediaTimingFunction(name: timing)
            layer.setValue(to, forKeyPath: key)
            layer.add(a, forKey: key)
        }
        // Projector flickers on.
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [0, 0.8, 0.2, 1, 0.6, 1]
        flicker.keyTimes = [0, 0.15, 0.3, 0.5, 0.65, 1]
        flicker.duration = 0.7
        flicker.beginTime = now + 0.2
        flicker.fillMode = .backwards
        glow.opacity = 1
        glow.add(flicker, forKey: "flicker")
        // Beam sweeps open and finds the ticket.
        animate(beam, "opacity", from: 0, to: 1, at: 0.5, duration: 0.6)
        animate(beamMask, "path", from: beamPath(spread: 0.02).cgPath, to: beamPath(spread: 0.32).cgPath, at: 0.5, duration: 1.0, timing: .easeOut)
        // Ticket draws itself, then fills in.
        animate(ticket, "strokeEnd", from: 0, to: 1, at: 0.9, duration: 1.1)
        animate(ticket, "fillColor", from: UIColor.clear.cgColor, to: Theme.amber.cgColor, at: 1.8, duration: 0.5)
        animate(ticket, "shadowOpacity", from: 0, to: 0.6, at: 1.8, duration: 0.6)
        animate(glyphs, "opacity", from: 0, to: 1, at: 2.1, duration: 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { Haptics.soft() }

        wordmark.transform = CGAffineTransform(translationX: 0, y: 16)
        tagline.transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(withDuration: 0.8, delay: 2.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.wordmark.alpha = 1; self.wordmark.transform = .identity
        }
        UIView.animate(withDuration: 0.8, delay: 2.25, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.tagline.alpha = 1; self.tagline.transform = .identity
        }
    }
}

// MARK: - Beat 2: pick what you've loved

private final class PickerView: UIView {
    var onChange: (([Title]) -> Void)?
    private let field = UIView()
    private let tray = UIView()
    private let trayLabel = UILabel()
    private var animator: UIDynamicAnimator?
    private let collision = UICollisionBehavior()
    private let noise = UIFieldBehavior.noiseField(smoothness: 0.95, animationSpeed: 0.35)
    /// Weak pull toward the middle so posters pile loosely instead of sticking to the edges.
    private let spring = UIFieldBehavior.springField()
    private let body = UIDynamicItemBehavior()
    private var posters: [UIButton: Title] = [:]
    private var picked: [Title] = []
    private var loaded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        let heading = UILabel()
        heading.text = "What have you loved?"
        heading.font = Theme.serif(.largeTitle, weight: .heavy)
        heading.textColor = Theme.paper
        heading.numberOfLines = 0
        heading.accessibilityTraits = .header
        let sub = UILabel()
        sub.text = "Tap a few you've seen. They go straight into your ticket box."
        sub.font = Theme.sans(.body)
        sub.textColor = Theme.muted
        sub.numberOfLines = 0
        [heading, sub].forEach { $0.adjustsFontForContentSizeCategory = true }
        let header = UIStackView(arrangedSubviews: [heading, sub])
        header.axis = .vertical
        header.spacing = 8

        field.clipsToBounds = false
        tray.layer.cornerRadius = 20
        tray.layer.cornerCurve = .continuous
        tray.layer.borderWidth = 1.5
        tray.layer.borderColor = Theme.amber.withAlphaComponent(0.5).cgColor
        tray.backgroundColor = Theme.amber.withAlphaComponent(0.06)
        trayLabel.font = Theme.mono(.caption1, weight: .bold)
        trayLabel.textColor = Theme.amber
        trayLabel.text = "YOUR TICKET BOX"
        tray.addSubview(trayLabel)
        trayLabel.translatesAutoresizingMaskIntoConstraints = false

        [header, field, tray].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.bottomAnchor.constraint(equalTo: tray.topAnchor, constant: -12),
            tray.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 8),
            tray.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -8),
            tray.heightAnchor.constraint(equalToConstant: 96),
            tray.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -84),
            trayLabel.topAnchor.constraint(equalTo: tray.topAnchor, constant: 10),
            trayLabel.leadingAnchor.constraint(equalTo: tray.leadingAnchor, constant: 14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !loaded, field.bounds.height > 100 else { return }
        loaded = true
        Task { await load() }
    }

    private func load() async {
        async let movies = TMDB.shared.titles(Reel(name: "", path: "movie/popular"))
        async let shows = TMDB.shared.titles(Reel(name: "", path: "tv/popular"))
        let all = ((try? await movies) ?? []).prefix(9) + ((try? await shows) ?? []).prefix(7)
        let titles = Array(all).shuffled()
        let still = UIAccessibility.isReduceMotionEnabled || UIAccessibility.isVoiceOverRunning
        let size = CGSize(width: 78, height: 117)
        let columns = max(Int(field.bounds.width / (size.width + 14)), 1)
        let rows = (titles.count + columns - 1) / columns
        let rowStep = (field.bounds.height - size.height - 12) / CGFloat(max(rows - 1, 1))

        for (i, title) in titles.enumerated() {
            let poster = UIButton(type: .custom)
            poster.frame = CGRect(origin: .zero, size: size)
            poster.imageView?.contentMode = .scaleAspectFill
            poster.clipsToBounds = true
            poster.layer.cornerRadius = 8
            poster.layer.cornerCurve = .continuous
            poster.backgroundColor = Theme.inkRaised
            poster.accessibilityLabel = title.name
            poster.accessibilityHint = "Adds to your seen titles"
            if let url = TMDB.imageURL(title.posterPath, .poster) {
                Task { poster.setImage(await ImageLoader.shared.image(url), for: .normal) }
            }
            poster.addAction(UIAction { [weak self, weak poster] _ in
                guard let self, let poster else { return }
                pick(poster)
            }, for: .primaryActionTriggered)
            let col = i % columns, row = i / columns
            let gridX = (CGFloat(col) + 0.5) * field.bounds.width / CGFloat(columns)
            // Staggered rows so the posters read as a scattered pile rather than a grid.
            let gridY = CGFloat(row) * rowStep + size.height / 2 + 6
            poster.center = CGPoint(x: gridX + (row % 2 == 0 ? -8 : 8), y: gridY)
            if !still { poster.transform = CGAffineTransform(rotationAngle: .random(in: -0.15...0.15)) }
            poster.alpha = 0
            field.addSubview(poster)
            posters[poster] = title
            UIView.animate(withDuration: 0.5, delay: Double(i) * 0.04) { poster.alpha = 1 }
        }
        guard !still else { return }

        let animator = UIDynamicAnimator(referenceView: field)
        collision.translatesReferenceBoundsIntoBoundary = true
        noise.strength = 0.6
        noise.region = UIRegion(size: field.bounds.size)
        noise.position = CGPoint(x: field.bounds.midX, y: field.bounds.midY)
        spring.strength = 0.12
        spring.region = noise.region
        spring.position = noise.position
        body.resistance = 1.2
        body.angularResistance = 4
        body.elasticity = 0.3
        posters.keys.forEach { collision.addItem($0); noise.addItem($0); spring.addItem($0); body.addItem($0) }
        [collision, noise, spring, body].forEach(animator.addBehavior)
        self.animator = animator
    }

    private func pick(_ poster: UIButton) {
        guard let title = posters.removeValue(forKey: poster) else { return }
        collision.removeItem(poster)
        noise.removeItem(poster)
        spring.removeItem(poster)
        body.removeItem(poster)
        poster.isUserInteractionEnabled = false
        picked.append(title)
        Haptics.thunk()

        // Drop it into the tray, fanned with the others like stubs in a box.
        let slot = picked.count - 1
        let target = tray.convert(CGPoint(x: 38 + CGFloat(slot % 12) * 26, y: 60), to: field)
        let reduce = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduce ? 0.2 : 0.55, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
            poster.center = target
            poster.transform = CGAffineTransform(scaleX: 0.5, y: 0.5).rotated(by: reduce ? 0 : CGFloat(slot % 2 == 0 ? -0.12 : 0.1))
        } completion: { _ in
            Haptics.soft()
            self.field.bringSubviewToFront(poster)
        }
        trayLabel.text = "YOUR TICKET BOX · \(picked.count)"
        UIAccessibility.post(notification: .announcement, argument: "\(title.name) added. \(picked.count) picked.")
        onChange?(picked)
    }
}

// MARK: - Beat 3: services

private final class ServicesBeatView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let heading = UILabel()
        heading.text = "Where do you watch?"
        heading.font = Theme.serif(.largeTitle, weight: .heavy)
        heading.textColor = Theme.paper
        heading.numberOfLines = 0
        heading.accessibilityTraits = .header
        let region = Locale.current.localizedString(forRegionCode: Prefs.region) ?? Prefs.region
        let sub = UILabel()
        sub.text = "We'll flag what's already on your services in \(region). You can change this any time in Settings."
        sub.font = Theme.sans(.body)
        sub.textColor = Theme.muted
        sub.numberOfLines = 0
        [heading, sub].forEach { $0.adjustsFontForContentSizeCategory = true }
        let header = UIStackView(arrangedSubviews: [heading, sub])
        header.axis = .vertical
        header.spacing = 8
        let picker = ServicesPickerView()
        picker.limit = 20
        [header, picker].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -8),
            picker.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -80),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
