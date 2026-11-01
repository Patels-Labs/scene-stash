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

final class TextCell: UICollectionViewCell {
    let label = UILabel.make(Theme.text(.body), Theme.text.withAlphaComponent(0.82), lines: 5)
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        label.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A cast list line from a theatre programme: the name set large, dotted leaders, the role.
final class CompanyCell: UICollectionViewCell {
    private let name = UILabel.make(Theme.display(28, weight: .black))
    private let role = UILabel.make(Theme.text(.footnote), Theme.secondary)
    private let leader = CAShapeLayer()
    private let rule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        leader.strokeColor = UIColor(white: 1, alpha: 0.28).cgColor
        leader.lineWidth = 1.5
        leader.lineCap = .round
        leader.lineDashPattern = [0.1, 5]
        contentView.layer.addSublayer(leader)
        name.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.6
        role.textAlignment = .right
        role.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rule.backgroundColor = Theme.hairline
        [name, role, rule].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            name.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            name.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            name.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            role.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            role.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            role.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 28),
            rule.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = name.frame.minY + name.font.ascender + 1
        let from = name.frame.maxX + 8, to = role.text?.isEmpty == false ? role.frame.minX - 8 : contentView.bounds.maxX
        let p = UIBezierPath()
        if to > from { p.move(to: CGPoint(x: from, y: y)); p.addLine(to: CGPoint(x: to, y: y)) }
        leader.path = p.cgPath
    }

    func configure(_ cast: CastMember) {
        name.text = cast.name.uppercased()
        role.text = cast.character
        accessibilityLabel = [cast.name, cast.character.map { "as \($0)" }].compactMap { $0 }.joined(separator: " ")
        setNeedsLayout()
    }
}

/// Where to watch, as tickets: services you have are printed in the film's colour, the rest are outlines.
final class ProviderTicketCell: UICollectionViewCell {
    private let caption = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let name = UILabel.make(Theme.display(24, weight: .black))
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        shape.lineWidth = 1.5
        shape.lineDashPattern = [5, 4]
        contentView.layer.addSublayer(shape)
        let stack = UIStackView(arrangedSubviews: [caption, name])
        stack.axis = .vertical
        stack.spacing = 4
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.path = TicketShape.path(in: contentView.bounds.insetBy(dx: 1, dy: 1), corner: 12, notch: 7).cgPath
    }

    func configure(_ provider: Provider, mine: Bool, accent: UIColor) {
        caption.setCaps(mine ? "Yours · included" : "Included", kern: 1.2)
        name.text = provider.providerName.uppercased()
        shape.fillColor = mine ? accent.cgColor : nil
        shape.strokeColor = mine ? nil : UIColor(white: 1, alpha: 0.28).cgColor
        shape.lineDashPattern = mine ? nil : [5, 4]
        caption.textColor = mine ? UIColor(white: 0, alpha: 0.7) : Theme.tertiary
        name.textColor = mine ? .black : Theme.text
        accessibilityLabel = provider.providerName + (mine ? ", one of your services" : "")
    }
}

/// A streaming service logo; yours get a lit ring and a check.
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

/// An episode as a programme line: its number set big, the title, and a hole to punch.
final class EpisodeCell: UICollectionViewCell {
    let punch = PunchButton()
    var onPunch: (() -> Void)?
    private let number = UILabel.make(Theme.display(44, weight: .black))
    private let name = UILabel.make(Theme.text(.headline, weight: .semibold), Theme.text, lines: 2)
    private let detail = UILabel.make(Theme.text(.caption1), Theme.secondary, lines: 2)
    private let rule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        number.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let text = UIStackView(arrangedSubviews: [name, detail])
        text.axis = .vertical
        text.spacing = 3
        let row = UIStackView(arrangedSubviews: [number, text, punch])
        row.alignment = .center
        row.spacing = 12
        rule.backgroundColor = Theme.hairline
        [row, rule].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rule.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        punch.addAction(UIAction { [weak self] _ in self?.onPunch?() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ episode: Episode, watched: Bool, aired: Bool, next: Bool, accent: UIColor) {
        number.text = String(format: "%02d", episode.episodeNumber)
        number.textColor = next ? accent : watched ? Theme.tertiary : Theme.text
        name.text = episode.name
        var bits: [String] = []
        if next { bits.append("Up next") }
        if !aired { bits.append(episode.airDate.flatMap(DateText.pretty).map { "Airs \($0)" } ?? "Not aired yet") }
        else if let runtime = episode.runtime { bits.append("\(runtime) min") }
        if let date = episode.airDate.flatMap(DateText.pretty), aired { bits.append(date) }
        detail.text = bits.joined(separator: " · ")
        punch.accent = accent
        punch.set(watched, animated: false)
        punch.isEnabled = aired
        punch.alpha = aired ? 1 : 0.3
        punch.accessibilityLabel = "Episode \(episode.episodeNumber), \(episode.name)"
        contentView.alpha = aired ? 1 : 0.55
    }
}

/// "Where you are" in a film: the time, a strip to scrub, and what that means for tonight.
final class FilmProgressCell: UICollectionViewCell {
    var onCommit: ((Int) -> Void)?
    var onFinished: (() -> Void)?
    let strip = FilmStripView()
    private let caption = UILabel.make(Theme.label(), Theme.secondary)
    private let percent = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let clock = UILabel.make(Theme.display(54, weight: .black))
    private let total = UILabel.make(Theme.display(24, weight: .black), Theme.tertiary)
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let finished = PillButton("Finished it", image: "checkmark")
    private let restart = PillButton("Start over", inverted: true)
    private var runtime = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(white: 1, alpha: 0.06)
        contentView.layer.cornerRadius = 22
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        caption.setCaps("Where you are")
        let top = UIStackView(arrangedSubviews: [caption, UIView(), percent])
        let time = UIStackView(arrangedSubviews: [clock, total, UIView()])
        time.alignment = .lastBaseline
        time.spacing = 8
        strip.interactive = true
        strip.heightAnchor.constraint(equalToConstant: 64).isActive = true
        strip.addAction(UIAction { [weak self] _ in self?.scrubbed() }, for: .valueChanged)
        strip.addAction(UIAction { [weak self] _ in self?.commit() }, for: .editingDidEnd)
        finished.addAction(UIAction { [weak self] _ in self?.onFinished?() }, for: .primaryActionTriggered)
        restart.addAction(UIAction { [weak self] _ in
            self?.strip.value = 0
            self?.commit()
        }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [finished, restart])
        buttons.distribution = .fillEqually
        buttons.spacing = 10
        let stack = UIStackView(arrangedSubviews: [top, time, strip, note, buttons])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: top)
        stack.setCustomSpacing(16, after: note)
        contentView.addSubview(stack)
        stack.pin(to: contentView, inset: 18)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(position: Int, runtime: Int, accent: UIColor) {
        self.runtime = runtime
        strip.runtime = runtime
        strip.tint = accent
        percent.textColor = accent
        if !strip.isTracking { strip.value = Double(position) / Double(max(runtime * 60, 1)) }
        total.text = "/ " + ProgrammeCell.clock(runtime * 60)
        scrubbed()
    }

    private var seconds: Int { Int((strip.value * Double(runtime)).rounded()) * 60 }

    private func scrubbed() {
        clock.text = ProgrammeCell.clock(seconds)
        percent.setCaps("\(Int(strip.value * 100))%")
        let left = runtime - seconds / 60
        restart.isHidden = seconds == 0
        if seconds == 0 {
            note.text = "Not started. Drag the strip to where you are, and it'll wait for you on Tonight."
        } else {
            let done = Date.now.addingTimeInterval(TimeInterval(left * 60)).formatted(.dateTime.hour().minute())
            note.text = "\(left) minutes left. Start now and you're done by \(done)."
        }
    }

    private func commit() {
        Haptics.soft()
        // Dragging right to the end means you've finished it.
        if strip.value >= 0.99 { onFinished?() } else { onCommit?(seconds) }
    }
}

/// The punch card plus its totals, framed like a card from the box office.
final class PunchCardCell: UICollectionViewCell {
    let card = PunchCardView()
    private let caption = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let fine = UILabel.make(Theme.label(.caption2), Theme.tertiary)
    private let left = UILabel.make(Theme.display(34, weight: .black))
    private let leftCaption = UILabel.make(Theme.label(.caption2), Theme.secondary)
    private let share = UILabel.make(Theme.display(34, weight: .black))
    private let shareCaption = UILabel.make(Theme.label(.caption2), Theme.secondary)
    private let perforation = CAShapeLayer()
    private let divider = CardView()
    private let footer = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 20
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        caption.setCaps("Punch card")
        fine.setCaps("Admit one per episode", kern: 1)
        let top = UIStackView(arrangedSubviews: [caption, UIView(), fine])
        top.alignment = .firstBaseline
        leftCaption.textAlignment = .left
        share.textAlignment = .right
        shareCaption.textAlignment = .right
        let a = UIStackView(arrangedSubviews: [left, leftCaption]); a.axis = .vertical; a.spacing = 2
        let b = UIStackView(arrangedSubviews: [share, shareCaption]); b.axis = .vertical; b.spacing = 2; b.alignment = .trailing
        [a, UIView(), b].forEach(footer.addArrangedSubview)
        perforation.lineWidth = 2
        perforation.lineDashPattern = [5, 4]
        perforation.fillColor = nil
        divider.layer.addSublayer(perforation)
        divider.heightAnchor.constraint(equalToConstant: 2).isActive = true
        divider.onLayout = { [weak self] b in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 0, y: b.midY)); p.addLine(to: CGPoint(x: b.maxX, y: b.midY))
            self?.perforation.path = p.cgPath
        }
        let stack = UIStackView(arrangedSubviews: [top, card, divider, footer])
        stack.axis = .vertical
        stack.spacing = 16
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func systemLayoutSizeFitting(_ target: CGSize, withHorizontalFittingPriority h: UILayoutPriority, verticalFittingPriority v: UILayoutPriority) -> CGSize {
        // The card's height follows its width, so measure it for the width we're given.
        let cardHeight = PunchCardView.height(for: target.width - 32, rows: card.rows)
        card.constraints.filter { $0.firstAttribute == .height }.forEach { card.removeConstraint($0) }
        card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
        return super.systemLayoutSizeFitting(target, withHorizontalFittingPriority: h, verticalFittingPriority: v)
    }

    func configure(remaining: Int, minutes: Int, punched: Int, total: Int, accent: UIColor) {
        contentView.backgroundColor = accent.withAlphaComponent(0.07)
        contentView.layer.borderColor = accent.withAlphaComponent(0.28).cgColor
        perforation.strokeColor = accent.withAlphaComponent(0.28).cgColor
        caption.textColor = accent
        share.textColor = accent
        card.tint = accent
        left.text = remaining == 0 ? "CAUGHT UP" : "\(remaining) LEFT"
        leftCaption.setCaps(remaining == 0 ? "Every aired episode" : "About \(DateText.runtime(minutes))")
        share.text = "\(total == 0 ? 0 : punched * 100 / total)%"
        shareCaption.setCaps("Punched")
    }
}

/// "Stay seated": what's waiting during and after the credits, as a dashed ticket.
final class StingerCell: UICollectionViewCell {
    private let caption = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.accent)
    private let title = UILabel.make(Theme.display(26, weight: .black), Theme.text, lines: 0)
    private let detail = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let count = UILabel.make(Theme.display(34, weight: .black), Theme.accent)
    private let border = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Theme.accent.withAlphaComponent(0.08)
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        border.fillColor = nil
        border.lineWidth = 1.5
        border.lineDashPattern = [5, 4]
        border.strokeColor = Theme.accent.withAlphaComponent(0.45).cgColor
        contentView.layer.addSublayer(border)
        caption.setCaps("Stay seated")
        let extra = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)
        extra.setCaps("Extra")
        let stub = UIStackView(arrangedSubviews: [count, extra])
        stub.axis = .vertical
        stub.alignment = .center
        stub.spacing = 2
        stub.widthAnchor.constraint(equalToConstant: 62).isActive = true
        let text = UIStackView(arrangedSubviews: [caption, title, detail])
        text.axis = .vertical
        text.spacing = 4
        let row = UIStackView(arrangedSubviews: [text, stub])
        row.alignment = .center
        row.spacing = 12
        contentView.addSubview(row)
        row.pin(to: contentView, inset: 14)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.path = UIBezierPath(roundedRect: contentView.bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 16).cgPath
    }

    func configure(mid: Bool, after: Bool) {
        let n = (mid ? 1 : 0) + (after ? 1 : 0)
        count.text = "\(n)"
        switch (mid, after) {
        case (true, true):
            title.text = "SCENES DURING AND AFTER THE CREDITS"
            detail.text = "One partway through, one at the very end. Don't leave early."
        case (true, false):
            title.text = "A SCENE DURING THE CREDITS"
            detail.text = "Hang on through the first part of the credits."
        default:
            title.text = "A SCENE AFTER THE CREDITS"
            detail.text = "Wait for the very end."
        }
        accessibilityLabel = "Stay seated. " + (title.text ?? "").capitalized + ". " + (detail.text ?? "")
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

    static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
