import UIKit

/// First launch: the icon comes to life → a poster wall → "Watched it?" → streaming services → your library.
final class OnboardingViewController: UIViewController {
    private let stage = UIView()
    private let bar = UIStackView()
    private let button = CapsuleButton.primary("Get Started")
    private let skip = CapsuleButton.glass("Skip")
    private let intro = WallBeat(heading: "Every film.\nEvery episode.\nOne library.", body: "Track what you watch, find what's next, and plan movie nights with friends.")
    private let deck = DeckBeat()
    private let coldOpen = ColdOpen()
    private var opening: Task<Void, Never>?
    private var beat = 0
    private var current: UIView?
    private var titles: [Title] = []

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.advance() }, for: .primaryActionTriggered)
        skip.addAction(UIAction { [weak self] _ in self?.finish() }, for: .primaryActionTriggered)
        [button, skip].forEach { bar.addArrangedSubview($0) }
        bar.axis = .vertical
        bar.spacing = 10
        bar.alpha = 0
        [stage, bar].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(coldOpen)
        coldOpen.pin(to: view)
        coldOpen.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(settle)))
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.topAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -12),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Shelf.margin),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        show(intro, title: "Get Started")

        Task {
            async let movies = TMDB.shared.titles(Reel(name: "", path: "movie/popular"))
            async let shows = TMDB.shared.titles(Reel(name: "", path: "tv/popular"))
            async let classics = TMDB.shared.titles(Reel(name: "", path: "movie/top_rated"))
            let all = ((try? await movies) ?? []).prefix(10) + ((try? await shows) ?? []).prefix(8) + ((try? await classics) ?? []).prefix(8)
            var seen = Set<Int>()
            titles = all.filter { $0.posterPath != nil && seen.insert($0.id).inserted }.shuffled()
            intro.show(titles)
            deck.load(titles)
        }
    }

    // Started here rather than in viewDidLoad so a replay from Settings doesn't spend it under the cross-dissolve.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A tap during the replay's cross-dissolve may already have settled it.
        guard opening == nil, coldOpen.superview != nil, coldOpen.isUserInteractionEnabled else { return }
        if UIAccessibility.isReduceMotionEnabled || UIAccessibility.isVoiceOverRunning { return settle() }
        opening = Task {
            await coldOpen.play()
            // Give the posters a moment to arrive so the wall deals in full, but never wait on a dead network.
            var waited = 0
            while titles.isEmpty, waited < 12, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            settle()
        }
    }

    /// Ends the cold open wherever it is (a tap skips straight here) and deals in the wall.
    @objc private func settle() {
        guard coldOpen.superview != nil, coldOpen.isUserInteractionEnabled else { return }
        opening?.cancel()
        coldOpen.isUserInteractionEnabled = false
        intro.deal()
        let reduce = UIAccessibility.isReduceMotionEnabled
        Spring.move(response: 0.7, {
            self.coldOpen.alpha = 0
            if !reduce { self.coldOpen.ticket.transform = self.coldOpen.ticket.transform.scaledBy(x: 1.25, y: 1.25) }
        }, completion: { _ in self.coldOpen.removeFromSuperview() })
        if !reduce { bar.transform = CGAffineTransform(translationX: 0, y: 40) }
        Spring.move(response: 0.6, bounce: 0.2, delay: 0.7) {
            self.bar.alpha = 1
            self.bar.transform = .identity
        }
        UIAccessibility.post(notification: .screenChanged, argument: intro)
    }

    private func advance() {
        beat += 1
        switch beat {
        case 1:
            show(deck, title: "Continue")
        case 2:
            show(ServicesBeat(), title: "Continue")
        case 3:
            skip.isHidden = true
            show(finale(), title: "Open Scene Stash")
        default:
            Haptics.success()
            finish()
        }
    }

    private func show(_ next: UIView, title: String) {
        button.configuration?.title = title
        stage.addSubview(next)
        next.pin(to: stage)
        let old = current
        current = next
        UIAccessibility.post(notification: .screenChanged, argument: next)
        guard let old else { return }
        // Each beat pushes the last one off to the left, like turning a page forward.
        let reduce = UIAccessibility.isReduceMotionEnabled
        let shift = reduce ? 0 : stage.bounds.width * 0.3
        next.alpha = 0
        next.transform = CGAffineTransform(translationX: shift, y: 0)
        Spring.move(response: 0.55, {
            old.alpha = 0
            if !reduce { old.transform = CGAffineTransform(translationX: -shift, y: 0).scaledBy(x: 0.94, y: 0.94) }
            next.alpha = 1
            next.transform = .identity
        }, completion: { _ in old.removeFromSuperview() })
    }

    private func finish() {
        Prefs.onboarded = true
        Task { await Store.shared.backfillRuntimes() }
        dismiss(animated: true)
    }

    /// Up to three of the posters just added, or the wall again when nothing was.
    private func finale() -> UIView {
        let added = deck.stashed
        guard !added.isEmpty else {
            let wall = WallBeat(heading: "Your library is ready", body: "Find something in Search and add it to your library.")
            wall.show(titles)
            return wall
        }
        let arts = added.prefix(3).map { title in
            let art = ArtView(radius: 10)
            art.show(TMDB.imageURL(title.posterPath, .poster), name: title.name)
            art.widthAnchor.constraint(equalToConstant: Shelf.poster.width).isActive = true
            art.heightAnchor.constraint(equalToConstant: Shelf.poster.height).isActive = true
            return art
        }
        // Dealt up from below and fanned like a hand of cards.
        let reduce = UIAccessibility.isReduceMotionEnabled
        for (i, art) in arts.enumerated() {
            let tilt = CGFloat(i) - CGFloat(arts.count - 1) / 2
            let rest = CGAffineTransform(translationX: 0, y: abs(tilt) * 10).rotated(by: tilt * 0.1)
            art.alpha = 0
            art.transform = reduce ? rest : CGAffineTransform(translationX: tilt * 30, y: 160).rotated(by: tilt * 0.4)
            // Next runloop, once show(_:) has put the beat in the window.
            DispatchQueue.main.async {
                Spring.move(response: 0.7, bounce: 0.3, delay: 0.2 + Double(i) * 0.1) {
                    art.alpha = 1
                    art.transform = rest
                }
            }
        }
        let posters = UIStackView(arrangedSubviews: arts)
        posters.spacing = Shelf.gap
        posters.accessibilityElementsHidden = true
        let words = beatHeader("\(added.count) \(added.count == 1 ? "title" : "titles") in your library", body: "All set. Tonight's picks are waiting.")
        let stack = UIStackView(arrangedSubviews: [posters, words])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 28
        let beat = UIView()
        beat.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: beat.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: beat.leadingAnchor, constant: Shelf.margin),
            stack.trailingAnchor.constraint(equalTo: beat.trailingAnchor, constant: -Shelf.margin),
        ])
        return beat
    }
}

private func beatHeader(_ title: String, body: String) -> UIStackView {
    let heading = UILabel.make(Theme.text(.largeTitle, weight: .bold), lines: 0)
    heading.text = title
    heading.textAlignment = .center
    heading.accessibilityTraits = .header
    let sub = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)
    sub.text = body
    sub.textAlignment = .center
    let stack = UIStackView(arrangedSubviews: [heading, sub])
    stack.axis = .vertical
    stack.spacing = 8
    return stack
}

/// Rows of posters bleeding off the top and sides, fading to black behind a headline.
private final class WallBeat: UIView {
    private let tiles = (0..<16).map { _ in ArtView(radius: 10) }
    private let shade = CAGradientLayer()
    private let words: UIStackView

    init(heading: String, body: String) {
        words = beatHeader(heading, body: body)
        super.init(frame: .zero)
        clipsToBounds = true
        let rows = stride(from: 0, to: tiles.count, by: 4).map { i in
            let row = UIStackView(arrangedSubviews: Array(tiles[i..<i + 4]))
            row.spacing = Shelf.gap
            row.distribution = .fillEqually
            return row
        }
        let wall = UIStackView(arrangedSubviews: rows)
        wall.axis = .vertical
        wall.spacing = Shelf.gap
        wall.accessibilityElementsHidden = true
        shade.colors = [UIColor.clear.cgColor, Theme.bg.cgColor]
        shade.locations = [0.25, 0.68]
        addSubview(wall)
        layer.addSublayer(shade)
        addSubview(words)
        wall.translatesAutoresizingMaskIntoConstraints = false
        words.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(tiles.map { $0.heightAnchor.constraint(equalTo: $0.widthAnchor, multiplier: 1.5) } + [
            wall.topAnchor.constraint(equalTo: topAnchor),
            wall.centerXAnchor.constraint(equalTo: centerXAnchor),
            wall.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1.17),
            words.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Shelf.margin),
            words.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Shelf.margin),
            words.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.place(bounds)
    }

    func show(_ titles: [Title]) {
        for (tile, title) in zip(tiles, titles) { tile.show(TMDB.imageURL(title.posterPath, .poster), name: title.name) }
    }

    /// Posters rise in on a diagonal wave from the top-left, then the headline, then the line under it.
    func deal() {
        let lift = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX: 0, y: 60).scaledBy(x: 0.88, y: 0.88)
        for (i, tile) in tiles.enumerated() {
            tile.alpha = 0
            tile.transform = lift
            Spring.move(response: 0.9, delay: Double(i % 4 + i / 4) * 0.06) {
                tile.alpha = 1
                tile.transform = .identity
            }
        }
        for (i, line) in words.arrangedSubviews.enumerated() {
            line.alpha = 0
            line.transform = lift == .identity ? .identity : CGAffineTransform(translationX: 0, y: 24)
            Spring.move(response: 0.7, delay: 0.35 + Double(i) * 0.15) {
                line.alpha = 1
                line.transform = .identity
            }
        }
    }
}

/// The app icon coming to life: out of the dark, the ticket rises, its stub tears off, and the name lands under it.
private final class ColdOpen: UIView {
    let ticket = Ticket()
    private let halo = Halo()
    private let wordmark = UILabel.make(UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 40, weight: .black, width: .compressed)))
    private let tilt = CGAffineTransform(rotationAngle: -14 * .pi / 180)

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.bg // matches the launch screen, so the cut from launch is invisible
        accessibilityElementsHidden = true
        wordmark.attributedText = NSAttributedString(string: "SCENE STASH", attributes: [.kern: 2, .font: wordmark.font!, .foregroundColor: Theme.text])
        wordmark.textAlignment = .center
        [halo, ticket, wordmark].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        halo.pin(to: self)
        NSLayoutConstraint.activate([
            ticket.centerXAnchor.constraint(equalTo: centerXAnchor),
            ticket.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            ticket.widthAnchor.constraint(equalToConstant: 260),
            ticket.heightAnchor.constraint(equalTo: ticket.widthAnchor),
            wordmark.topAnchor.constraint(equalTo: ticket.bottomAnchor, constant: -36),
            wordmark.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        halo.alpha = 0
        ticket.alpha = 0
        ticket.transform = CGAffineTransform(translationX: 0, y: 120).scaledBy(x: 0.8, y: 0.8)
        wordmark.alpha = 0
        wordmark.transform = CGAffineTransform(translationX: 0, y: 20)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// About two and a half seconds. Returns early if cancelled; whoever cancels sets the end state.
    func play() async {
        func wait(_ seconds: Double) async -> Bool { (try? await Task.sleep(for: .seconds(seconds))) != nil }
        Spring.move(response: 1.6) { self.halo.alpha = 1 }
        guard await wait(0.2) else { return }
        Spring.move(response: 1.0, bounce: 0.12) {
            self.ticket.alpha = 1
            self.ticket.transform = self.tilt
        }
        guard await wait(1.0) else { return }
        Haptics.thunk()
        ticket.tear()
        guard await wait(0.3) else { return }
        Spring.move(response: 0.8) {
            self.wordmark.alpha = 1
            self.wordmark.transform = .identity
        }
        _ = await wait(1.1)
    }
}

/// The icon's low amber light, so the ticket sits in a room rather than on a void.
private final class Halo: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let glow = layer as! CAGradientLayer
        glow.type = .radial
        glow.colors = [UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.32).cgColor, UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.45)
        glow.endPoint = CGPoint(x: 1.25, y: 0.9)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The ticket from the app icon, drawn on the same 100-unit grid as Design/build_icon.swift.
private final class Ticket: UIView {
    private let body = TicketPiece(CGRect(x: 12, y: 31, width: 52, height: 38))
    private let stub = TicketPiece(CGRect(x: 64, y: 31, width: 22, height: 38))
    private let perforation = CAShapeLayer()
    private let letter = UILabel()

    init() {
        super.init(frame: .zero)
        perforation.fillColor = UIColor(white: 0, alpha: 0.55).cgColor
        letter.textColor = .black
        letter.text = "S"
        addSubview(body)
        layer.addSublayer(perforation)
        addSubview(letter)
        addSubview(stub)
        stub.layer.anchorPoint = CGPoint(x: 0.75, y: 0.5) // tips about the tear line, as in the icon
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Snaps the stub away to where it sits in the icon: dropped and tipped.
    func tear() {
        let u = bounds.width / 100
        Spring.move(response: 0.5, bounce: 0.45) {
            self.stub.transform = CGAffineTransform(rotationAngle: 11 * .pi / 180).concatenating(CGAffineTransform(translationX: 3.5 * u, y: 3.5 * u))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let u = bounds.width / 100
        body.bounds = bounds
        body.center = CGPoint(x: bounds.midX, y: bounds.midY)
        stub.bounds = bounds
        stub.center = CGPoint(x: 75 * u, y: 50 * u)
        perforation.place(bounds)
        let dots = CGMutablePath()
        for i in 0..<6 { dots.addEllipse(in: CGRect(x: 62.2 * u, y: (39 + CGFloat(i) * 4.4) * u, width: 1.6 * u, height: 1.6 * u)) }
        perforation.path = dots
        // The icon's display face: SF Pro Compressed Black, its cap height centred on (38, 50).
        let font = UIFont.systemFont(ofSize: 46 * u, weight: .black, width: .compressed)
        letter.font = font
        letter.sizeToFit()
        letter.center = CGPoint(x: 38 * u, y: 50 * u - (font.ascender - font.capHeight / 2) + letter.bounds.midY)
    }
}

/// One piece of the ticket: top-lit amber stock with the notches cut from the tear line, and its drop shadow.
private final class TicketPiece: UIView {
    private let rect: CGRect
    private let stock = CAGradientLayer()
    private let shape = CAShapeLayer()

    init(_ rect: CGRect) {
        self.rect = rect
        super.init(frame: .zero)
        stock.colors = [UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 1).cgColor, Theme.accent.cgColor]
        stock.startPoint = CGPoint(x: 0.5, y: rect.minY / 100)
        stock.endPoint = CGPoint(x: 0.5, y: rect.maxY / 100)
        stock.mask = shape
        layer.addSublayer(stock)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.7
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let u = bounds.width / 100
        let scaled = CGRect(x: rect.minX * u, y: rect.minY * u, width: rect.width * u, height: rect.height * u)
        let notches = CGMutablePath()
        for y: CGFloat in [31, 69] { notches.addEllipse(in: CGRect(x: 59.5 * u, y: (y - 4.5) * u, width: 9 * u, height: 9 * u)) }
        let path = CGPath(roundedRect: scaled, cornerWidth: 5 * u, cornerHeight: 5 * u, transform: nil).subtracting(notches)
        stock.place(bounds)
        shape.path = path
        layer.shadowPath = path
        layer.shadowOffset = CGSize(width: 0, height: 2.5 * u)
        layer.shadowRadius = 3 * u
    }
}

private enum Verdict {
    case seen, want, skip

    var label: String {
        switch self {
        case .seen: "Watched"
        case .want: "Save for Later"
        case .skip: "Not Watched"
        }
    }
}

/// One large poster at a time: swipe it, or use the buttons.
private final class DeckBeat: UIView {
    private(set) var stashed: [Title] = []
    private var queue: [Title] = []
    private var loaded = false
    private var cards: [(title: Title, art: ArtView)] = []
    private var watched = 0
    private var saved = 0
    private let deckArea = UIView()
    private let badge = GlassLabel()
    private let name = UILabel.make(Theme.text(.title3, weight: .semibold))
    private let meta = UILabel.make(Theme.text(.subheadline), Theme.secondary)
    private let tally = UILabel.make(Theme.text(.footnote, weight: .semibold), Theme.accent)
    private let buttons = UIStackView()
    private let empty = UILabel.make(Theme.text(.title2, weight: .bold), Theme.secondary, lines: 0)

    init() {
        super.init(frame: .zero)
        let header = beatHeader("Watched it?", body: "Swipe right if you've watched it, left if not, up to save it for later.")
        for label in [name, meta, tally] { label.textAlignment = .center }
        tally.text = " "
        empty.text = "That's all for now."
        empty.textAlignment = .center
        empty.isHidden = true
        badge.isHidden = true
        deckArea.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))

        for (symbol, label, verdict) in [("xmark", "Not watched", Verdict.skip), ("bookmark.fill", "Save for later", Verdict.want), ("checkmark", "Watched it", Verdict.seen)] {
            let button = CapsuleButton.circle(symbol, label: label)
            button.addAction(UIAction { [weak self] _ in self?.decide(verdict) }, for: .primaryActionTriggered)
            buttons.addArrangedSubview(button)
        }
        buttons.spacing = 20
        let info = UIStackView(arrangedSubviews: [name, meta, tally])
        info.axis = .vertical
        info.spacing = 2

        [header, deckArea, badge, info, buttons, empty].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        let fill = deckArea.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.72)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Shelf.margin),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Shelf.margin),
            deckArea.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 20),
            deckArea.centerXAnchor.constraint(equalTo: centerXAnchor),
            deckArea.widthAnchor.constraint(equalTo: deckArea.heightAnchor, multiplier: 2.0 / 3),
            deckArea.bottomAnchor.constraint(equalTo: info.topAnchor, constant: -14),
            fill,
            badge.topAnchor.constraint(equalTo: deckArea.topAnchor, constant: 14),
            badge.centerXAnchor.constraint(equalTo: deckArea.centerXAnchor),
            info.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Shelf.margin),
            info.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Shelf.margin),
            info.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            empty.centerXAnchor.constraint(equalTo: deckArea.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: deckArea.centerYAnchor),
            empty.widthAnchor.constraint(equalTo: deckArea.widthAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func load(_ titles: [Title]) {
        queue = titles
        loaded = true
        refill()
    }

    /// Keeps the next poster ready behind the current one.
    private func refill() {
        while cards.count < 2, !queue.isEmpty {
            let title = queue.removeFirst()
            let art = ArtView(radius: 12)
            art.show(TMDB.imageURL(title.posterPath, .posterLarge), name: title.name)
            art.accessibilityLabel = [title.name, title.year].compactMap { $0 }.joined(separator: ", ")
            art.accessibilityHint = "Use the buttons below to mark it watched, save it, or skip."
            // A loaded image must not push the deck past the size its constraints give it.
            art.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
            art.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
            deckArea.insertSubview(art, at: 0)
            art.pin(to: deckArea)
            cards.append((title, art))
        }
        for (i, card) in cards.enumerated() { card.art.isAccessibilityElement = i == 0 }
        let top = cards.first
        name.text = top?.title.name
        meta.text = top.map { [$0.title.mediaType == .movie ? "Film" : "TV Show", $0.title.year].compactMap { $0 }.joined(separator: " · ") }
        empty.isHidden = !(loaded && cards.isEmpty)
        buttons.isHidden = cards.isEmpty
        if let top { UIAccessibility.post(notification: .layoutChanged, argument: top.art) }
    }

    private func verdict(_ t: CGPoint, velocity v: CGPoint) -> Verdict? {
        if t.x > 110 || v.x > 900 { return .seen }
        if t.x < -110 || v.x < -900 { return .skip }
        if t.y < -120 || v.y < -900 { return .want }
        return nil
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let art = cards.first?.art else { return }
        let t = g.translation(in: self)
        switch g.state {
        case .changed:
            art.transform = CGAffineTransform(translationX: t.x, y: t.y)
            let preview = verdict(t, velocity: .zero)
            badge.text = preview?.label
            badge.isHidden = preview == nil
        case .ended, .cancelled:
            badge.isHidden = true
            if g.state == .ended, let thrown = verdict(t, velocity: g.velocity(in: self)) {
                decide(thrown)
            } else if UIAccessibility.isReduceMotionEnabled {
                art.transform = .identity
            } else {
                Spring.move { art.transform = .identity }
            }
        default: break
        }
    }

    private func decide(_ verdict: Verdict) {
        guard !cards.isEmpty else { return }
        let card = cards.removeFirst()
        let art = card.art
        art.isAccessibilityElement = false
        let now = art.transform
        let off: CGAffineTransform = switch verdict {
        case .seen: CGAffineTransform(translationX: bounds.width * 1.4, y: now.ty)
        case .skip: CGAffineTransform(translationX: -bounds.width * 1.4, y: now.ty)
        case .want: CGAffineTransform(translationX: now.tx, y: -bounds.height)
        }
        if verdict == .skip { Haptics.tap() } else { Haptics.thunk() }
        let reduce = UIAccessibility.isReduceMotionEnabled
        Spring.move({
            if reduce { art.alpha = 0 } else { art.transform = off }
        }, completion: { _ in art.removeFromSuperview() })

        switch verdict {
        case .seen: Store.shared.track(card.title, status: .seen); stashed.append(card.title); watched += 1
        case .want: Store.shared.track(card.title, status: .watchlist); stashed.append(card.title); saved += 1
        case .skip: break
        }
        let counts = [watched > 0 ? "\(watched) watched" : nil, saved > 0 ? "\(saved) saved" : nil].compactMap { $0 }
        tally.text = counts.isEmpty ? " " : counts.joined(separator: " · ")
        refill()
    }
}

/// A switch for each streaming service, subscriptions first.
private final class ServicesBeat: UIView {
    private let dataSource: UICollectionViewDiffableDataSource<Int, Provider>

    override init(frame: CGRect) {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = .clear
        let list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Provider> { cell, _, provider in
            var content = cell.defaultContentConfiguration()
            content.text = provider.providerName
            content.textProperties.color = Theme.text
            cell.contentConfiguration = content
            var background = cell.defaultBackgroundConfiguration()
            background.backgroundColor = Card.fill
            cell.backgroundConfiguration = background
            let logo = UIImageView()
            logo.layer.cornerRadius = 6
            logo.layer.cornerCurve = .continuous
            logo.clipsToBounds = true
            logo.translatesAutoresizingMaskIntoConstraints = false
            logo.widthAnchor.constraint(equalToConstant: 30).isActive = true
            logo.heightAnchor.constraint(equalToConstant: 30).isActive = true
            logo.setImage(TMDB.imageURL(provider.logoPath, .logo))
            let toggle = UISwitch()
            toggle.onTintColor = Theme.accent
            toggle.isOn = Prefs.services.contains(provider.providerId)
            toggle.accessibilityLabel = provider.providerName
            toggle.addAction(UIAction { [weak toggle] _ in
                guard let toggle else { return }
                if toggle.isOn { Prefs.services.insert(provider.providerId) } else { Prefs.services.remove(provider.providerId) }
            }, for: .valueChanged)
            cell.accessories = [
                .customView(configuration: .init(customView: logo, placement: .leading(displayed: .always))),
                .customView(configuration: .init(customView: toggle, placement: .trailing(displayed: .always))),
            ]
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: list) { collectionView, indexPath, provider in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: provider)
        }
        super.init(frame: frame)
        let region = Locale.current.localizedString(forRegionCode: Prefs.region) ?? Prefs.region
        let header = beatHeader("Where do you watch?", body: "Turn on the ones you pay for in \(region).")
        list.backgroundColor = .clear
        list.allowsSelection = false
        [header, list].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Shelf.margin),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Shelf.margin),
            list.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            list.leadingAnchor.constraint(equalTo: leadingAnchor),
            list.trailingAnchor.constraint(equalTo: trailingAnchor),
            list.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        Task {
            let providers = (try? await TMDB.shared.providers(region: Prefs.region)) ?? []
            // Rental storefronts aren't subscriptions, so they go last.
            let isStore: (Provider) -> Bool = { $0.providerName.contains("Store") || $0.providerName.hasSuffix("Channel") }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Provider>()
            snapshot.appendSections([0])
            snapshot.appendItems(Array((providers.filter { !isStore($0) } + providers.filter(isStore)).prefix(30)))
            await dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}
