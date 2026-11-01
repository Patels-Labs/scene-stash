import UIKit

/// Intro → "Seen it?" swipe deck → streaming services → your stash. Ambient light follows whatever poster is in focus.
final class OnboardingViewController: UIViewController {
    private let glow = GlowView()
    private let stage = UIView()
    private let button = PillButton("Start your stash")
    private var beat = 0
    private var current: UIView?
    private var titles: [Title] = []
    private var stashed: [Title] = []

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(glow)
        glow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: view.topAnchor),
            glow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glow.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.8),
        ])
        view.addSubview(stage)
        stage.pin(to: view)
        button.addAction(UIAction { [weak self] _ in self?.advance() }, for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        button.alpha = 0
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Theme.tertiary
        spinner.startAnimating()
        view.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)])

        Task {
            async let movies = TMDB.shared.titles(Reel(name: "", path: "movie/popular"))
            async let shows = TMDB.shared.titles(Reel(name: "", path: "tv/popular"))
            async let classics = TMDB.shared.titles(Reel(name: "", path: "movie/top_rated"))
            let all = ((try? await movies) ?? []).prefix(10) + ((try? await shows) ?? []).prefix(8) + ((try? await classics) ?? []).prefix(8)
            var seen = Set<Int>()
            titles = all.filter { $0.posterPath != nil && seen.insert($0.id).inserted }.shuffled()
            spinner.removeFromSuperview()
            let intro = IntroBeat(titles: Array(titles.prefix(6)), glow: glow)
            show(intro, title: "Start your stash", animated: false)
            intro.play()
            UIView.animate(withDuration: 0.6, delay: UIAccessibility.isReduceMotionEnabled ? 0 : 1.1) { self.button.alpha = 1 }
        }
    }

    private func advance() {
        Haptics.tap()
        beat += 1
        switch beat {
        case 1:
            let deck = DeckBeat(titles: titles, glow: glow)
            deck.onChange = { [weak self] stashed in
                self?.stashed = stashed
                self?.button.configuration?.title = stashed.isEmpty ? "Skip for now" : "Continue"
            }
            show(deck, title: "Skip for now", animated: true)
        case 2:
            show(ServicesBeat(), title: "Continue", animated: true)
        case 3:
            show(FinaleBeat(stashed: stashed, glow: glow), title: "Open Scene Stash", animated: true)
        default:
            finish()
        }
    }

    private func show(_ next: UIView, title: String, animated: Bool) {
        button.configuration?.title = title
        stage.addSubview(next)
        next.pin(to: stage)
        let old = current
        current = next
        guard animated, let old else { return }
        let reduce = UIAccessibility.isReduceMotionEnabled
        next.alpha = 0
        next.transform = reduce ? .identity : CGAffineTransform(scaleX: 1.06, y: 1.06)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            old.alpha = 0
            old.transform = reduce ? .identity : CGAffineTransform(scaleX: 0.92, y: 0.92)
            next.alpha = 1
            next.transform = .identity
        } completion: { _ in old.removeFromSuperview() }
        UIAccessibility.post(notification: .screenChanged, argument: next)
    }

    private func finish() {
        Prefs.onboarded = true
        Haptics.success()
        Task { await Store.shared.backfillRuntimes() }
        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseIn) {
            self.view.alpha = 0
            if !UIAccessibility.isReduceMotionEnabled { self.view.transform = CGAffineTransform(scaleX: 1.08, y: 1.08) }
        } completion: { _ in self.dismiss(animated: false) }
    }
}

// MARK: - Shared

private func beatHeader(step: String?, title: String, body: String) -> UIStackView {
    let caption = UILabel.make(Theme.label(), Theme.secondary)
    caption.setCaps(step)
    caption.isHidden = step == nil
    let heading = UILabel.make(Theme.display(52, weight: .black), lines: 0)
    heading.setDisplay(title.uppercased())
    heading.accessibilityTraits = .header
    let sub = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)
    sub.text = body
    let stack = UIStackView(arrangedSubviews: [caption, heading, sub])
    stack.axis = .vertical
    stack.spacing = 6
    stack.setCustomSpacing(10, after: heading)
    return stack
}

// MARK: - Beat 1: intro

/// A fanned hand of poster cards that keeps shuffling, over the line that says what this is.
private final class IntroBeat: UIView {
    private let titles: [Title]
    private weak var glow: GlowView?
    private var cards: [TiltCardView] = []
    private var index = 0
    private var timer: Timer?
    private let words: UIStackView

    init(titles: [Title], glow: GlowView) {
        self.titles = titles
        self.glow = glow
        words = beatHeader(step: nil, title: "Every film.\nEvery episode.\nOne stash.", body: "Track what you watch, find what's next, and keep every ticket.")
        super.init(frame: .zero)
        for i in 0..<3 {
            let card = TiltCardView()
            card.maxAngle = i == 0 ? 0.2 : 0.1
            card.cornerRadius = 18
            card.setPoster(titles[safe: i]?.posterPath, size: .posterLarge)
            cards.append(card)
        }
        cards.reversed().forEach(addSubview)
        cards[0].foil = true
        addSubview(words)
        words.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            words.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            words.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            words.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -92),
        ])
        glow.show(TMDB.imageURL(titles.first?.posterPath, .poster))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func removeFromSuperview() {
        timer?.invalidate()
        super.removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(bounds.width * 0.56, 260), h = w * 1.5
        let top = safeAreaInsets.top + max((words.frame.minY - safeAreaInsets.top - h) / 2 - 10, 16)
        for (i, card) in cards.enumerated() {
            card.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            card.center = CGPoint(x: bounds.midX, y: top + h / 2)
            if card.layer.animationKeys()?.isEmpty ?? true, card.alpha > 0 { card.transform = fan(i) }
        }
    }

    private func fan(_ i: Int) -> CGAffineTransform {
        switch i {
        case 1: CGAffineTransform(translationX: -56, y: 18).rotated(by: -0.16).scaledBy(x: 0.86, y: 0.86)
        case 2: CGAffineTransform(translationX: 56, y: 18).rotated(by: 0.16).scaledBy(x: 0.86, y: 0.86)
        default: .identity
        }
    }

    func play() {
        layoutIfNeeded()
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        for (i, card) in cards.enumerated() {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: 260).rotated(by: CGFloat(i) * 0.2 - 0.2)
            UIView.animate(withDuration: 1.0, delay: 0.1 + Double(2 - i) * 0.12, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3) {
                card.alpha = 1
                card.transform = self.fan(i)
            }
        }
        for (i, v) in words.arrangedSubviews.enumerated() {
            v.alpha = 0
            v.transform = CGAffineTransform(translationX: 0, y: 24)
            UIView.animate(withDuration: 0.8, delay: 0.55 + Double(i) * 0.12, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                v.alpha = 1; v.transform = .identity
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Haptics.soft() }
        timer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.shuffle() }
        }
    }

    /// The front card flips over to the next poster; the light in the room follows it.
    private func shuffle() {
        guard titles.count > 3 else { return }
        index = (index + 1) % titles.count
        let front = cards[0]
        UIView.transition(with: front, duration: 0.7, options: [.transitionFlipFromRight, .allowAnimatedContent]) {
            front.setPoster(self.titles[self.index].posterPath, size: .posterLarge)
        }
        cards[1].setPoster(titles[(index + 1) % titles.count].posterPath)
        cards[2].setPoster(titles[(index + 2) % titles.count].posterPath)
        glow?.show(TMDB.imageURL(titles[index].posterPath, .poster))
    }
}

// MARK: - Beat 2: swipe deck

private enum Verdict { case seen, want, skip }

private final class SwipeCard: UIView {
    let title: Title
    let card = TiltCardView()
    private let stamps: [Verdict: UILabel]

    init(title: Title) {
        self.title = title
        func stamp(_ text: String, _ color: UIColor, _ angle: CGFloat) -> UILabel {
            let l = UILabel.make(Theme.display(40, weight: .black), color)
            l.text = " \(text) "
            l.layer.borderColor = color.cgColor
            l.layer.borderWidth = 4
            l.layer.cornerRadius = 10
            l.transform = CGAffineTransform(rotationAngle: angle)
            l.alpha = 0
            return l
        }
        stamps = [.seen: stamp("SEEN", .white, -0.25), .skip: stamp("NOPE", Theme.secondary, 0.25), .want: stamp("LATER", Theme.accent, -0.08)]
        super.init(frame: .zero)
        card.cornerRadius = 20
        card.maxAngle = 0.12
        card.setPoster(title.posterPath, size: .posterLarge)
        addSubview(card)
        card.pin(to: self)
        for (verdict, label) in stamps {
            addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            switch verdict {
            case .seen: NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: topAnchor, constant: 28), label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22)])
            case .skip: NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: topAnchor, constant: 28), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22)])
            case .want: NSLayoutConstraint.activate([label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40), label.centerXAnchor.constraint(equalTo: centerXAnchor)])
            }
        }
        isAccessibilityElement = true
        accessibilityLabel = [title.name, title.year].compactMap { $0 }.joined(separator: ", ")
        accessibilityHint = "Use the buttons below to mark it seen, save it, or skip."
    }
    required init?(coder: NSCoder) { fatalError() }

    func showStamp(for translation: CGPoint) {
        let vertical = -translation.y > abs(translation.x)
        stamps[.seen]?.alpha = vertical ? 0 : max(0, min(1, translation.x / 90))
        stamps[.skip]?.alpha = vertical ? 0 : max(0, min(1, -translation.x / 90))
        stamps[.want]?.alpha = vertical ? max(0, min(1, -translation.y / 90)) : 0
    }

    func stamp(_ verdict: Verdict) { stamps.forEach { $0.value.alpha = $0.key == verdict ? 1 : 0 } }
}

private final class DeckBeat: UIView {
    var onChange: (([Title]) -> Void)?
    private var queue: [Title]
    private var cards: [SwipeCard] = []
    private weak var glow: GlowView?
    private let deckArea = UIView()
    private let name = UILabel.make(Theme.text(.title3, weight: .semibold))
    private let meta = UILabel.make(Theme.label(), Theme.secondary)
    private let tally = UILabel.make(Theme.label(.caption1, weight: .bold), Theme.accent)
    private var stashed: [Title] = []
    private var counts: [Verdict: Int] = [:]
    private let empty = UILabel.make(Theme.display(34, weight: .black), Theme.secondary, lines: 0)

    init(titles: [Title], glow: GlowView) {
        queue = titles
        self.glow = glow
        super.init(frame: .zero)
        let header = beatHeader(step: "Step 1 of 2", title: "Seen it?", body: "Swipe right if you've seen it, left if not, up to save it for later.")
        name.textAlignment = .center
        meta.textAlignment = .center
        empty.text = "THAT'S THE STACK."
        empty.textAlignment = .center
        empty.isHidden = true
        deckArea.isUserInteractionEnabled = false

        let skip = Self.round("xmark", tint: Theme.secondary, label: "Not seen")
        let want = Self.round("bookmark.fill", tint: Theme.accent, label: "Save for later")
        let seen = Self.round("checkmark", tint: .white, label: "Seen it")
        skip.addAction(UIAction { [weak self] _ in self?.decide(.skip) }, for: .primaryActionTriggered)
        want.addAction(UIAction { [weak self] _ in self?.decide(.want) }, for: .primaryActionTriggered)
        seen.addAction(UIAction { [weak self] _ in self?.decide(.seen) }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [skip, want, seen])
        buttons.spacing = 22
        let info = UIStackView(arrangedSubviews: [name, meta])
        info.axis = .vertical
        info.spacing = 4

        [header, tally, deckArea, info, buttons, empty].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        let fill = deckArea.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.72)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            tally.topAnchor.constraint(equalTo: header.topAnchor),
            tally.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            deckArea.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 30),
            deckArea.centerXAnchor.constraint(equalTo: centerXAnchor),
            deckArea.widthAnchor.constraint(equalTo: deckArea.heightAnchor, multiplier: 2 / 3),
            deckArea.bottomAnchor.constraint(equalTo: info.topAnchor, constant: -20),
            fill,
            info.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            info.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            info.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -18),
            buttons.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttons.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -84),
            empty.centerXAnchor.constraint(equalTo: deckArea.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: deckArea.centerYAnchor),
            empty.widthAnchor.constraint(equalTo: deckArea.widthAnchor),
        ])
        refill()
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func round(_ symbol: String, tint: UIColor, label: String) -> UIButton {
        var config = UIButton.Configuration.glass()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold))
        config.cornerStyle = .capsule
        let b = UIButton(configuration: config)
        b.tintColor = tint
        b.accessibilityLabel = label
        b.widthAnchor.constraint(equalToConstant: 66).isActive = true
        b.heightAnchor.constraint(equalToConstant: 66).isActive = true
        return b
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, card) in cards.enumerated() where card.gestureRecognizers?.first?.state != .changed {
            card.bounds = deckArea.bounds
            card.center = CGPoint(x: deckArea.frame.midX, y: deckArea.frame.midY)
            if card.layer.animationKeys()?.isEmpty ?? true { card.transform = rest(i) }
        }
    }

    private func rest(_ depth: Int) -> CGAffineTransform {
        // Scaling shrinks toward the centre, so lift each card enough that its top edge peeks out above the one in front.
        let s = 1 - CGFloat(depth) * 0.06
        let lift = deckArea.bounds.height * (1 - s) / 2 + CGFloat(depth) * 12
        return CGAffineTransform(translationX: 0, y: -lift).scaledBy(x: s, y: s)
    }

    /// Keeps three cards on the table, newest at the back.
    private func refill() {
        while cards.count < 3, !queue.isEmpty {
            let card = SwipeCard(title: queue.removeFirst())
            card.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
            if let last = cards.last { insertSubview(card, belowSubview: last) } else { insertSubview(card, aboveSubview: deckArea) }
            cards.append(card)
            card.alpha = 0
            setNeedsLayout(); layoutIfNeeded()
            card.transform = rest(cards.count)
            UIView.animate(withDuration: 0.4) { card.alpha = 1 }
        }
        for (i, card) in cards.enumerated() {
            card.isUserInteractionEnabled = i == 0
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) { card.transform = self.rest(i) }
        }
        let top = cards.first?.title
        name.text = top?.name
        meta.setCaps([top.map { $0.mediaType == .movie ? "Film" : "Series" }, top?.year].compactMap { $0 }.joined(separator: " · "))
        glow?.show(TMDB.imageURL(top?.posterPath, .poster))
        empty.isHidden = !cards.isEmpty
        if let top = cards.first { UIAccessibility.post(notification: .layoutChanged, argument: top) }
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let card = g.view as? SwipeCard else { return }
        let t = g.translation(in: self), v = g.velocity(in: self)
        switch g.state {
        case .changed:
            card.transform = CGAffineTransform(translationX: t.x, y: t.y).rotated(by: t.x / bounds.width * 0.5)
            card.showStamp(for: t)
        case .ended, .cancelled:
            if t.x > 110 || v.x > 900 { throwCard(card, .seen, velocity: v) }
            else if t.x < -110 || v.x < -900 { throwCard(card, .skip, velocity: v) }
            else if t.y < -120 || v.y < -900 { throwCard(card, .want, velocity: v) }
            else {
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
                    card.transform = self.rest(0)
                    card.showStamp(for: .zero)
                }
            }
        default: break
        }
    }

    private func decide(_ verdict: Verdict) {
        guard let card = cards.first else { return }
        card.stamp(verdict)
        throwCard(card, verdict, velocity: .zero)
    }

    private func throwCard(_ card: SwipeCard, _ verdict: Verdict, velocity: CGPoint) {
        guard cards.first === card else { return }
        cards.removeFirst()
        card.isUserInteractionEnabled = false
        let off: CGPoint = switch verdict {
        case .seen: CGPoint(x: bounds.width * 1.4, y: velocity.y * 0.2)
        case .skip: CGPoint(x: -bounds.width * 1.4, y: velocity.y * 0.2)
        case .want: CGPoint(x: velocity.x * 0.2, y: -bounds.height)
        }
        if verdict == .skip { Haptics.tap() } else { Haptics.thunk() }
        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseOut) {
            card.transform = CGAffineTransform(translationX: off.x, y: off.y).rotated(by: off.x / self.bounds.width * 0.4)
        } completion: { _ in card.removeFromSuperview() }

        counts[verdict, default: 0] += 1
        switch verdict {
        case .seen: Store.shared.track(card.title, status: .seen); stashed.append(card.title)
        case .want: Store.shared.track(card.title, status: .watchlist); stashed.append(card.title)
        case .skip: break
        }
        tally.setCaps([counts[.seen].map { "\($0) seen" }, counts[.want].map { "\($0) saved" }].compactMap { $0 }.joined(separator: " · "))
        onChange?(stashed)
        refill()
    }
}

// MARK: - Beat 3: services

private final class ServicesBeat: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let region = Locale.current.localizedString(forRegionCode: Prefs.region) ?? Prefs.region
        let header = beatHeader(step: "Step 2 of 2", title: "Where do you watch?", body: "Pick your services in \(region). We'll flag what's already yours to stream.")
        let picker = ServicesPickerView()
        picker.limit = 21
        [header, picker].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            picker.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -78),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Beat 4: finale

/// What you just stashed lands in one neat pile, with the count rolling up beside it.
private final class FinaleBeat: UIView {
    private let stashed: [Title]
    private var cards: [TiltCardView] = []
    private let number = UILabel.make(Theme.display(140, weight: .black))
    private let words: UIStackView
    private var displayLink: CADisplayLink?
    private var start: CFTimeInterval = 0

    init(stashed: [Title], glow: GlowView) {
        self.stashed = stashed
        let caption = stashed.isEmpty ? "Your stash is ready" : stashed.count == 1 ? "Title in your stash" : "Titles in your stash"
        words = beatHeader(step: nil, title: caption, body: stashed.isEmpty ? "Find something in Discover and tear off your first ticket." : "All set. Tonight's picks are waiting.")
        super.init(frame: .zero)
        number.text = "0"
        number.isHidden = stashed.isEmpty
        number.accessibilityLabel = "\(stashed.count)"
        for title in stashed.prefix(5).reversed() {
            let card = TiltCardView()
            card.setPoster(title.posterPath)
            card.cornerRadius = 12
            addSubview(card)
            cards.append(card)
        }
        cards.last?.foil = true
        let stack = UIStackView(arrangedSubviews: [number, words])
        stack.axis = .vertical
        stack.spacing = -6
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -92),
        ])
        glow.show(TMDB.imageURL(stashed.first?.posterPath, .poster))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, start == 0, bounds.width > 0 else { return }
        let w = min(bounds.width * 0.5, 210), h = w * 1.5
        let textTop = subviews.compactMap { $0 as? UIStackView }.first?.frame.minY ?? bounds.height * 0.6
        let centerY = safeAreaInsets.top + (textTop - safeAreaInsets.top) / 2
        let mid = CGFloat(cards.count - 1) / 2
        for (i, card) in cards.enumerated() {
            let offset = CGFloat(i) - mid
            let final = CGAffineTransform(translationX: offset * 14, y: -abs(offset) * 2).rotated(by: offset * 0.07)
            card.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            card.center = CGPoint(x: bounds.midX, y: centerY)
            card.transform = UIAccessibility.isReduceMotionEnabled ? final : CGAffineTransform(translationX: (i % 2 == 0 ? -1 : 1) * 300, y: -200).rotated(by: 0.8)
            UIView.animate(withDuration: 0.8, delay: 0.1 + Double(i) * 0.09, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.2) {
                card.transform = final
            } completion: { _ in if i == self.cards.count - 1 { Haptics.soft() } }
        }
        start = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        let p = min((CACurrentMediaTime() - start) / 1.1, 1)
        let eased = 1 - pow(1 - p, 3)
        number.text = "\(Int((Double(stashed.count) * eased).rounded()))"
        if p >= 1 { displayLink?.invalidate(); displayLink = nil }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
