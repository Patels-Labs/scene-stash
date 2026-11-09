import UIKit

/// Hosts a long-lived view (the hero) inside a cell so its state survives reconfiguration.
final class HostCell: UICollectionViewCell {
    func host(_ view: UIView) {
        guard view.superview !== contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        contentView.addSubview(view)
        view.pin(to: contentView)
    }
}

/// The grouped-card background Apple uses for information blocks.
enum Card {
    static let fill = UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
    static let rule = UIColor(red: 0.33, green: 0.33, blue: 0.345, alpha: 0.6)

    static func style(_ view: UIView) {
        view.backgroundColor = fill
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
    }
}

/// "Where You Are" in a film: the time, a slider to drag to where you stopped, and when you'll be done.
/// While Start Watching is running it follows the clock instead.
final class WhereYouAreCell: UICollectionViewCell {
    var onCommit: ((Int) -> Void)?
    private let time = UILabel.make(Theme.text(.title1, weight: .bold).monospacedDigits)
    private let left = UILabel.make(Theme.text(.footnote), Theme.secondary)
    private let slider = UISlider()
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private var runtime = 0
    private var live: WatchSession.State?
    private var ticker: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        Card.style(contentView)
        slider.minimumTrackTintColor = Theme.accent
        slider.accessibilityLabel = "Where you are"
        slider.addAction(UIAction { [weak self] _ in self?.scrubbed() }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in self?.commit() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        left.textAlignment = .right
        let top = UIStackView(arrangedSubviews: [time, left])
        top.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [top, slider, note])
        stack.axis = .vertical
        stack.spacing = 10
        contentView.addSubview(stack)
        stack.pin(to: contentView, inset: 16)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        ticker?.invalidate()
    }

    func configure(position: Int, runtime: Int, live session: WatchSession.State?) {
        self.runtime = runtime
        live = session
        ticker?.invalidate()
        slider.isEnabled = session == nil
        if let session {
            if session.pausedAt == nil {
                ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            }
            tick()
        } else {
            if !slider.isTracking { slider.value = Float(position) / Float(max(runtime * 60, 1)) }
            scrubbed()
        }
    }

    private var seconds: Int { Int((slider.value * Float(runtime)).rounded()) * 60 }

    private func tick() {
        guard let live else { return }
        let elapsed = Int(live.elapsed)
        slider.value = Float(live.elapsed) / Float(max(runtime * 60, 1))
        time.text = String(format: "%d:%02d:%02d", elapsed / 3600, elapsed % 3600 / 60, elapsed % 60)
        let remaining = max(runtime * 60 - elapsed, 0) / 60
        left.text = "\(DateText.runtime(remaining)) left"
        note.text = live.pausedAt == nil
            ? "Now Showing, done by \(Date.now.addingTimeInterval(TimeInterval(remaining * 60)).formatted(date: .omitted, time: .shortened)). Pause from the Lock Screen for ads or a break."
            : "Paused. The end time moves with you."
    }

    private func scrubbed() {
        guard live == nil else { return }
        time.text = DateText.clock(seconds)
        let remaining = max(runtime - seconds / 60, 0)
        left.text = seconds == 0 ? DateText.runtime(runtime) : "\(DateText.runtime(remaining)) left"
        note.text = seconds == 0
            ? "Not started. Start Watching keeps time on the Lock Screen, or drag to where you are."
            : "Done by \(Date.now.addingTimeInterval(TimeInterval(remaining * 60)).formatted(date: .omitted, time: .shortened)) if you carry on now."
        slider.accessibilityValue = "\(DateText.clock(seconds)) of \(DateText.clock(runtime * 60))"
    }

    private func commit() {
        guard live == nil else { return }
        onCommit?(seconds)
        Haptics.tap()
    }
}

/// An icon, a title and a line, on a card: the after-credits scene, and other one-line facts.
final class FactCell: UICollectionViewCell {
    private let icon = UIImageView()
    private let title = UILabel.make(Theme.text(.body, weight: .semibold))
    private let detail = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        Card.style(contentView)
        let tile = UIView()
        tile.backgroundColor = Theme.accent.withAlphaComponent(0.18)
        tile.layer.cornerRadius = 10
        tile.addSubview(icon)
        icon.tintColor = Theme.accent
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = .init(pointSize: 17, weight: .semibold)
        icon.pin(to: tile)
        tile.widthAnchor.constraint(equalToConstant: 40).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [tile, text])
        row.spacing = 14
        row.alignment = .center
        contentView.addSubview(row)
        row.pin(to: contentView, inset: 14)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(symbol: String, title: String, detail: String) {
        icon.image = UIImage(systemName: symbol)
        self.title.text = title
        self.detail.text = detail
        accessibilityLabel = "\(title). \(detail)"
    }
}

/// Your rating, 1 to 10, as a row of round buttons. Tapping the chosen one clears it.
final class RatingRow: UIView {
    var onChange: ((Int) -> Void)?
    private(set) var value = 0
    private var buttons: [UIButton] = []

    init(inset: CGFloat = Shelf.margin) {
        super.init(frame: .zero)
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInset = .init(top: 0, left: inset, bottom: 0, right: inset)
        let row = UIStackView()
        row.spacing = 8
        for n in 1...10 {
            var c = UIButton.Configuration.filled()
            c.title = "\(n)"
            c.cornerStyle = .capsule
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a; a.font = Theme.text(.body, weight: .bold); return a
            }
            let b = UIButton(configuration: c)
            b.accessibilityLabel = "\(n) out of 10"
            b.addAction(UIAction { [weak self] _ in self?.tap(n) }, for: .primaryActionTriggered)
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            buttons.append(b)
            row.addArrangedSubview(b)
        }
        addSubview(scroll)
        scroll.pin(to: self)
        scroll.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ rating: Int) {
        value = rating
        for (i, b) in buttons.enumerated() {
            let on = i + 1 == rating
            b.configuration?.baseBackgroundColor = on ? Theme.accent : UIColor(white: 0.47, alpha: 0.24)
            b.configuration?.baseForegroundColor = on ? .black : .white
            b.accessibilityTraits = on ? [.button, .selected] : .button
        }
    }

    private func tap(_ n: Int) {
        set(n == value ? 0 : n)
        Haptics.tap()
        onChange?(value)
    }
}

/// The rating row as a page section.
final class RatingCell: UICollectionViewCell {
    let row = RatingRow()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(row)
        row.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// An episode as a tall card: the still with its number, name and a few lines over it, and a tick when watched.
final class EpisodeLockup: UICollectionViewCell {
    private let art = ArtView(radius: 12)
    private let shade = CAGradientLayer()
    private let label = UILabel.make(Theme.text(.caption1, weight: .semibold), Theme.secondary)
    private let name = UILabel.make(Theme.text(.body, weight: .semibold), Theme.text, lines: 2)
    private let blurb = UILabel.make(Theme.text(.footnote), UIColor(white: 1, alpha: 0.7), lines: 3)
    private let meta = UILabel.make(Theme.text(.footnote), UIColor(white: 1, alpha: 0.85))
    private let tick = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(art)
        art.pin(to: contentView)
        shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.88).cgColor]
        shade.locations = [0.2, 0.72]
        art.layer.addSublayer(shade)
        tick.tintColor = Theme.accent
        tick.preferredSymbolConfiguration = .init(pointSize: 24, weight: .semibold)
        tick.backgroundColor = .black
        tick.layer.cornerRadius = 12
        let text = UIStackView(arrangedSubviews: [label, name, blurb, meta])
        text.axis = .vertical
        text.spacing = 2
        text.setCustomSpacing(8, after: blurb)
        [text, tick].forEach { art.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: art.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: art.trailingAnchor, constant: -16),
            text.bottomAnchor.constraint(equalTo: art.bottomAnchor, constant: -12),
            tick.topAnchor.constraint(equalTo: art.topAnchor, constant: 10),
            tick.trailingAnchor.constraint(equalTo: art.trailingAnchor, constant: -10),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = art.bounds
    }

    func configure(_ e: Episode, watched: Bool, aired: Bool, next: Bool, runtime: Int?) {
        art.show(TMDB.imageURL(e.stillPath, .backdrop), name: nil)
        label.text = "Episode \(e.episodeNumber)"
        name.text = e.name
        blurb.text = e.overview
        let length = (e.runtime ?? runtime).map { "\($0)m" }
        if !aired {
            meta.text = e.airDate.flatMap(DateText.pretty).map { "Airs \($0)" } ?? "Coming soon"
        } else if next {
            meta.text = ["Up next", length].compactMap { $0 }.joined(separator: " · ")
        } else {
            meta.text = length
        }
        tick.isHidden = !watched
        contentView.alpha = aired ? 1 : 0.55
        accessibilityLabel = "Episode \(e.episodeNumber), \(e.name)" + (watched ? ", watched" : "") + (aired ? "" : ", not out yet")
        accessibilityHint = aired ? (watched ? "Double tap to mark as not watched" : "Double tap to mark as watched") : nil
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.97) } }
}

/// "Season 2 ⌃⌄" with a menu of seasons, how many you've watched, and a slim bar per episode.
final class SeasonHeader: UICollectionReusableView {
    static let kind = "season-header"
    let picker = UIButton(configuration: .plain())
    private let count = UILabel.make(Theme.text(.footnote), Theme.secondary)
    private let bars = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        picker.configuration?.contentInsets = .zero
        picker.configuration?.imagePlacement = .trailing
        picker.configuration?.imagePadding = 6
        picker.configuration?.image = UIImage(systemName: "chevron.up.chevron.down")?.withTintColor(Theme.secondary, renderingMode: .alwaysOriginal)
        picker.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 13, weight: .bold)
        picker.configuration?.baseForegroundColor = Theme.text
        picker.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = Theme.text(.title2, weight: .semibold); return a
        }
        picker.showsMenuAsPrimaryAction = true
        bars.spacing = 4
        bars.distribution = .fillEqually
        bars.heightAnchor.constraint(equalToConstant: 4).isActive = true
        let top = UIStackView(arrangedSubviews: [picker, UIView(), count])
        top.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [top, bars])
        stack.axis = .vertical
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `states`: per aired-or-not episode, 2 watched, 1 up next, 0 not yet.
    func configure(season: Int, menu: UIMenu, states: [Int]) {
        picker.configuration?.title = "Season \(season)"
        picker.menu = menu
        let watched = states.filter { $0 == 2 }.count
        count.text = states.isEmpty ? nil : "\(watched) of \(states.count) watched"
        bars.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Past about 30 episodes the bars are too thin to read; one bar shows the share instead.
        let shown = states.count <= 30 ? states : []
        for s in shown {
            let bar = UIView()
            bar.layer.cornerRadius = 2
            bar.backgroundColor = s == 2 ? Theme.accent : s == 1 ? Theme.accent.withAlphaComponent(0.45) : UIColor(white: 0.47, alpha: 0.36)
            bars.addArrangedSubview(bar)
        }
        bars.isHidden = shown.isEmpty
        picker.accessibilityLabel = "Season \(season), \(count.text ?? ""). Choose season"
    }
}

/// A row in How to Watch: the service's logo, its name, and whether you have it.
final class ProviderRowCell: UICollectionViewCell {
    private let logo = UIImageView()
    private let name = UILabel.make(Theme.text(.body))
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary)
    private let rule = UIView()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Card.fill
        contentView.layer.cornerCurve = .continuous
        logo.layer.cornerRadius = 10
        logo.clipsToBounds = true
        logo.backgroundColor = Theme.surfaceHigh
        chevron.tintColor = Theme.tertiary
        chevron.preferredSymbolConfiguration = .init(pointSize: 13, weight: .semibold)
        chevron.contentMode = .center
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        rule.backgroundColor = Card.rule
        let text = UIStackView(arrangedSubviews: [name, note])
        text.axis = .vertical
        let row = UIStackView(arrangedSubviews: [logo, text, chevron])
        row.spacing = 14
        row.alignment = .center
        [row, rule].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 44), logo.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
            rule.topAnchor.constraint(equalTo: contentView.topAnchor),
            rule.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ provider: Provider, mine: Bool, first: Bool, last: Bool) {
        logo.setImage(TMDB.imageURL(provider.logoPath, .logo))
        name.text = provider.providerName
        note.text = mine ? "On one of your services" : "Streaming"
        note.textColor = mine ? Theme.accent : Theme.secondary
        rule.isHidden = first
        contentView.layer.cornerRadius = first || last ? 14 : 0
        var corners: CACornerMask = []
        if first { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if last { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        contentView.layer.maskedCorners = corners
        accessibilityLabel = "\(provider.providerName), \(note.text ?? "")"
    }
}

/// A streaming service in Settings and onboarding: its logo, name, and a tick when it's yours.
final class ProviderCell: UICollectionViewCell {
    private let logo = UIImageView()
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let name = UILabel.make(Theme.text(.caption2, weight: .medium), Theme.secondary, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        logo.layer.cornerRadius = 15
        logo.layer.cornerCurve = .continuous
        logo.clipsToBounds = true
        logo.backgroundColor = Theme.surface
        name.textAlignment = .center
        check.preferredSymbolConfiguration = .init(pointSize: 18, weight: .bold)
        check.tintColor = Theme.accent
        check.backgroundColor = .black
        check.layer.cornerRadius = 10
        let stack = UIStackView(arrangedSubviews: [logo, name])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 7
        contentView.addSubview(stack)
        contentView.addSubview(check)
        [stack, check].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 56), logo.heightAnchor.constraint(equalToConstant: 56),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            check.centerXAnchor.constraint(equalTo: logo.trailingAnchor, constant: -2),
            check.centerYAnchor.constraint(equalTo: logo.topAnchor, constant: 2),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ provider: Provider, mine: Bool, accent: UIColor) {
        logo.setImage(TMDB.imageURL(provider.logoPath, .logo))
        name.text = provider.providerName
        logo.layer.borderWidth = mine ? 2.5 : 0
        logo.layer.borderColor = accent.cgColor
        check.tintColor = accent
        check.isHidden = !mine
        name.textColor = mine ? Theme.text : Theme.secondary
        logo.alpha = mine ? 1 : 0.85
        accessibilityLabel = provider.providerName
        accessibilityTraits = mine ? [.button, .selected] : .button
    }
}

enum DateText {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ string: String) -> Date? { parser.date(from: string) }
    static func pretty(_ string: String) -> String? { date(string)?.formatted(.dateTime.month(.abbreviated).day().year()) }
    static func isPast(_ string: String?) -> Bool { string.flatMap(date).map { $0 <= .now } ?? false }

    /// "1:34" for a position in seconds.
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, seconds % 3600 / 60)
    }

    static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
