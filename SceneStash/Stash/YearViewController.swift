import UIKit

/// Your year so far as a reel of cards you tap through, each one shareable as an image.
final class YearViewController: UIViewController {
    private struct Year {
        var minutes = 0, films = 0, episodes = 0, bestStreak = 0
        var tens: [Title] = []
        var topShow: (title: Title, episodes: Int, minutes: Int)?
        var busiestMonth: (String, Int)?
    }

    private let year = Calendar.current.component(.year, from: .now)
    private var cards: [UIView] = []
    private var index = 0
    private let stage = UIView()
    private let bars = UIStackView()
    private let glow = CAGradientLayer()

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        view.layer.addSublayer(glow)

        let stats = compute()
        cards = makeCards(stats)
        bars.spacing = 4
        bars.distribution = .fillEqually
        for _ in cards {
            let bar = UIView()
            bar.backgroundColor = UIColor(white: 1, alpha: 0.3)
            bar.layer.cornerRadius = 1.5
            bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
            bars.addArrangedSubview(bar)
        }
        let close = UIButton(configuration: .glass())
        close.configuration?.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        let share = PillButton("Share this reel", image: "square.and.arrow.up")
        share.addAction(UIAction { [weak self] _ in self?.shareCard() }, for: .primaryActionTriggered)

        [stage, bars, close, share].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            bars.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bars.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bars.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            close.topAnchor.constraint(equalTo: bars.bottomAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stage.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 4),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: share.topAnchor, constant: -16),
            share.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            share.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            share.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        stage.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        show(0, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        glow.frame = CGRect(x: -view.bounds.width * 0.4, y: view.bounds.height * 0.1, width: view.bounds.width * 1.8, height: view.bounds.height * 0.8)
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        let forward = g.location(in: stage).x > stage.bounds.width * 0.3
        let next = index + (forward ? 1 : -1)
        guard cards.indices.contains(next) else { if forward { dismiss(animated: true) }; return }
        Haptics.tap()
        show(next, animated: true)
    }

    private static let tints: [UIColor] = [Theme.accent, UIColor(red: 0.85, green: 0.34, blue: 0.25, alpha: 1), UIColor(red: 0.25, green: 0.67, blue: 0.75, alpha: 1),
                                           UIColor(red: 0.6, green: 0.4, blue: 0.95, alpha: 1), UIColor(red: 0.45, green: 0.75, blue: 0.35, alpha: 1), Theme.accent]

    private func show(_ i: Int, animated: Bool) {
        let old = cards[index]
        index = i
        let card = cards[i]
        stage.addSubview(card)
        card.pin(to: stage)
        for (n, bar) in bars.arrangedSubviews.enumerated() { bar.backgroundColor = UIColor(white: 1, alpha: n <= i ? 1 : 0.3) }
        let tint = Self.tints[i % Self.tints.count]
        glow.colors = [tint.withAlphaComponent(0.5).cgColor, tint.withAlphaComponent(0).cgColor]
        UIAccessibility.post(notification: .screenChanged, argument: card)
        guard animated, old !== card else { return }
        card.alpha = 0
        card.transform = UIAccessibility.isReduceMotionEnabled ? .identity : CGAffineTransform(translationX: 30, y: 0)
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
            old.alpha = 0
            card.alpha = 1
            card.transform = .identity
        } completion: { _ in old.removeFromSuperview(); old.alpha = 1 }
    }

    private func shareCard() {
        // The card as an image on black, with the glow and a small credit line.
        let size = CGSize(width: 1080 / 3, height: 1920 / 3)
        let card = cards[index]
        let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }()).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let tint = Self.tints[index % Self.tints.count]
            let g = CGGradient(colorsSpace: nil, colors: [tint.withAlphaComponent(0.5).cgColor, tint.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width, options: [])
            let scale = min(size.width / card.bounds.width, (size.height - 60) / card.bounds.height)
            ctx.cgContext.translateBy(x: (size.width - card.bounds.width * scale) / 2, y: 30)
            ctx.cgContext.scaleBy(x: scale, y: scale)
            card.drawHierarchy(in: card.bounds, afterScreenUpdates: true)
        }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }

    // MARK: Stats

    private func compute() -> Year {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        let films = Store.shared.all(.seen).filter { $0.mediaType == .movie && ($0.watchedAt ?? .distantPast) >= start }
        let episodes = Store.shared.episodes().filter { ($0.watchedAt ?? .distantPast) >= start }
        var y = Year()
        y.films = films.count
        y.episodes = episodes.count
        y.minutes = films.reduce(0) { $0 + Int($1.runtime) } + episodes.reduce(0) { $0 + Int($1.runtime) }
        y.tens = Store.shared.all().filter { $0.rating >= 10 }.map(\.title)
        if let (show, eps) = Dictionary(grouping: episodes, by: \.showID).max(by: { $0.value.count < $1.value.count }),
           let tracked = Store.shared.tracked(Int(show), .tv) {
            y.topShow = (tracked.title, eps.count, eps.reduce(0) { $0 + Int($1.runtime) })
        }
        let dates = films.compactMap(\.watchedAt) + episodes.compactMap(\.watchedAt)
        if let (month, count) = Dictionary(grouping: dates) { cal.component(.month, from: $0) }.mapValues(\.count).max(by: { $0.value < $1.value }) {
            y.busiestMonth = (cal.monthSymbols[month - 1], count)
        }
        let days = Set(dates.map { cal.startOfDay(for: $0) }).sorted()
        var run = 0, best = 0, previous: Date?
        for day in days {
            run = previous.flatMap { cal.dateComponents([.day], from: $0, to: day).day } == 1 ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        y.bestStreak = best
        return y
    }

    // MARK: Cards

    private func makeCards(_ y: Year) -> [UIView] {
        let hours = y.minutes / 60
        var cards = [
            card(kicker: "Your \(year), on film", lines: ["\(hours) HOURS", "IN THE DARK."], accent: 1,
                 footer: "\(y.films) film\(y.films == 1 ? "" : "s") · \(y.episodes) episode\(y.episodes == 1 ? "" : "s")"),
        ]
        if !y.tens.isEmpty {
            cards.append(posterCard(kicker: "Your top billing", lines: ["THE ONES", "YOU GAVE", "A TEN."], titles: y.tens,
                                    stats: [("\(y.tens.count)", "Perfect tens"), ("\(hours)", "Hours lit"), ("\(y.bestStreak)", "Best streak")]))
        }
        if let top = y.topShow {
            cards.append(posterCard(kicker: "Most punched card", lines: [top.title.name.uppercased()], titles: [top.title],
                                    stats: [("\(top.episodes)", top.episodes == 1 ? "Episode" : "Episodes"), (DateText.runtime(top.minutes), "Watched")]))
        }
        if let (month, count) = y.busiestMonth {
            cards.append(card(kicker: "Your busiest month", lines: [month.uppercased() + "."], accent: 0, footer: "\(count) things watched. Popcorn budget: questionable."))
        }
        if y.bestStreak > 1 {
            cards.append(card(kicker: "Longest run", lines: ["\(y.bestStreak) DAYS", "IN A ROW."], accent: 0, footer: "Something on, every single night."))
        }
        cards.append(card(kicker: "That's a wrap", lines: ["SEE YOU", "AT THE", "MOVIES."], accent: 2, footer: "Scene Stash · \(year)"))
        return cards
    }

    /// Big display lines; the line at `accent` is tinted.
    private func card(kicker: String, lines: [String], accent: Int, footer: String) -> UIView {
        let k = UILabel.make(Theme.label(.caption1, weight: .bold), Theme.secondary)
        k.setCaps(kicker)
        let big = UILabel.make(Theme.display(76, weight: .black), Theme.text, lines: 0)
        big.adjustsFontSizeToFitWidth = true
        big.minimumScaleFactor = 0.5
        let text = NSMutableAttributedString()
        for (i, line) in lines.enumerated() {
            text.append(NSAttributedString(string: line + (i < lines.count - 1 ? "\n" : ""), attributes: [.foregroundColor: i == accent ? Self.tints[(index + 1) % Self.tints.count] : Theme.text]))
        }
        let style = NSMutableParagraphStyle(); style.lineHeightMultiple = 0.86
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        big.attributedText = text
        let f = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)
        f.text = footer
        let stack = UIStackView(arrangedSubviews: [k, big, f])
        stack.axis = .vertical
        stack.spacing = 14
        return wrap(stack, label: ([kicker] + lines + [footer]).joined(separator: ". "))
    }

    private func posterCard(kicker: String, lines: [String], titles: [Title], stats: [(String, String)]) -> UIView {
        let k = UILabel.make(Theme.label(.caption1, weight: .bold), Theme.secondary)
        k.setCaps(kicker)
        let big = UILabel.make(Theme.display(64, weight: .black), Theme.text, lines: 0)
        big.setDisplay(lines.joined(separator: "\n"))
        big.adjustsFontSizeToFitWidth = true
        big.minimumScaleFactor = 0.5
        let fan = UIView()
        fan.heightAnchor.constraint(equalToConstant: 230).isActive = true
        for (i, t) in titles.prefix(3).enumerated().reversed() {
            let c = TiltCardView()
            c.setPoster(t.posterPath)
            c.cornerRadius = 12
            c.foil = i == 0
            fan.addSubview(c)
            c.translatesAutoresizingMaskIntoConstraints = false
            let offset: CGFloat = i == 0 ? 0 : (i == 1 ? -86 : 86)
            NSLayoutConstraint.activate([
                c.widthAnchor.constraint(equalToConstant: i == 0 ? 146 : 124), c.heightAnchor.constraint(equalTo: c.widthAnchor, multiplier: 1.5),
                c.centerXAnchor.constraint(equalTo: fan.centerXAnchor, constant: offset), c.centerYAnchor.constraint(equalTo: fan.centerYAnchor, constant: i == 0 ? 0 : 14),
            ])
            c.transform = CGAffineTransform(rotationAngle: i == 0 ? 0 : (i == 1 ? -0.2 : 0.2))
        }
        let row = UIStackView(arrangedSubviews: stats.map { value, caption in
            let v = UILabel.make(Theme.display(44, weight: .black)); v.text = value
            let c = UILabel.make(Theme.label(), Theme.secondary); c.setCaps(caption)
            let s = UIStackView(arrangedSubviews: [v, c]); s.axis = .vertical; s.spacing = 2
            return s
        })
        row.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [k, big, fan, row])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(26, after: big)
        stack.setCustomSpacing(26, after: fan)
        return wrap(stack, label: ([kicker] + lines + stats.map { "\($0.0) \($0.1)" }).joined(separator: ". "))
    }

    private func wrap(_ content: UIView, label: String) -> UIView {
        let v = UIView()
        v.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -22),
            content.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        v.isAccessibilityElement = true
        v.accessibilityLabel = label
        v.accessibilityHint = "Tap to go to the next card"
        return v
    }
}
