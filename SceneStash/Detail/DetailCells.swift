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

final class CastCell: UICollectionViewCell {
    private let photo = UIImageView()
    private let name = UILabel.make(Theme.text(.footnote, weight: .semibold), Theme.text, lines: 2)
    private let role = UILabel.make(Theme.text(.caption2), Theme.secondary, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 38
        photo.backgroundColor = Theme.surface
        photo.tintColor = Theme.tertiary
        [name, role].forEach { $0.textAlignment = .center }
        let stack = UIStackView(arrangedSubviews: [photo, name, role])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.setCustomSpacing(10, after: photo)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            photo.widthAnchor.constraint(equalToConstant: 76), photo.heightAnchor.constraint(equalToConstant: 76),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ cast: CastMember) {
        photo.setImage(TMDB.imageURL(cast.profilePath, .profile), placeholder: UIImage(systemName: "person.fill"))
        name.text = cast.name
        role.text = cast.character
        accessibilityLabel = [cast.name, cast.character.map { "as \($0)" }].compactMap { $0 }.joined(separator: " ")
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

final class ChipCell: UICollectionViewCell {
    private let label = UILabel.make(Theme.label(.caption1, weight: .bold))
    var accent = Theme.accent

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        contentView.layer.cornerRadius = 18
        contentView.layer.cornerCurve = .continuous
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ text: String, selected: Bool, progress: String?) {
        label.setCaps(text + (progress.map { "  \($0)" } ?? ""), kern: 1)
        label.textColor = selected ? .black : Theme.text
        contentView.backgroundColor = selected ? accent : Theme.surfaceHigh
        accessibilityLabel = text + (progress.map { ", \($0) watched" } ?? "")
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}

final class EpisodeCell: UICollectionViewCell {
    let punch = PunchButton()
    var onPunch: (() -> Void)?
    private let still = UIImageView()
    private let number = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let name = UILabel.make(Theme.text(.headline, weight: .semibold), Theme.text, lines: 2)
    private let detail = UILabel.make(Theme.text(.caption1), Theme.secondary, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        still.contentMode = .scaleAspectFill
        still.clipsToBounds = true
        still.layer.cornerRadius = 10
        still.layer.cornerCurve = .continuous
        still.backgroundColor = Theme.surface
        let text = UIStackView(arrangedSubviews: [number, name, detail])
        text.axis = .vertical
        text.spacing = 3
        let row = UIStackView(arrangedSubviews: [still, text, punch])
        row.alignment = .center
        row.spacing = 14
        contentView.addSubview(row)
        row.pin(to: contentView)
        NSLayoutConstraint.activate([
            still.widthAnchor.constraint(equalToConstant: 116),
            still.heightAnchor.constraint(equalToConstant: 66),
        ])
        punch.addAction(UIAction { [weak self] _ in self?.onPunch?() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ episode: Episode, watched: Bool, aired: Bool, accent: UIColor) {
        still.setImage(TMDB.imageURL(episode.stillPath, .still))
        number.setCaps("Episode \(episode.episodeNumber)" + (episode.runtime.map { " · \($0) min" } ?? ""), kern: 1)
        number.textColor = accent
        name.text = episode.name
        detail.text = aired ? episode.overview : episode.airDate.flatMap(DateText.pretty).map { "Airs \($0)" } ?? "Not aired yet"
        punch.accent = accent
        punch.set(watched, animated: false)
        punch.isEnabled = aired
        punch.alpha = aired ? 1 : 0.3
        punch.accessibilityLabel = "Episode \(episode.episodeNumber), \(episode.name)"
        contentView.alpha = aired ? 1 : 0.55
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
