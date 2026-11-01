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
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = Theme.serif(.body, weight: .regular)
        label.textColor = Theme.paper.withAlphaComponent(0.85)
        label.adjustsFontForContentSizeCategory = true
        contentView.addSubview(label)
        label.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class CastCell: UICollectionViewCell {
    private let photo = UIImageView()
    private let name = UILabel()
    private let role = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 40
        photo.backgroundColor = Theme.inkRaised
        photo.tintColor = Theme.muted
        name.font = Theme.sans(.footnote, weight: .semibold)
        name.textColor = Theme.paper
        role.font = Theme.sans(.caption2)
        role.textColor = Theme.muted
        [name, role].forEach { $0.textAlignment = .center; $0.numberOfLines = 2; $0.adjustsFontForContentSizeCategory = true }
        let stack = UIStackView(arrangedSubviews: [photo, name, role])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.setCustomSpacing(8, after: photo)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            photo.widthAnchor.constraint(equalToConstant: 80), photo.heightAnchor.constraint(equalToConstant: 80),
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

final class ProviderCell: UICollectionViewCell {
    private let logo = UIImageView()
    private let name = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        logo.layer.cornerRadius = 12
        logo.layer.cornerCurve = .continuous
        logo.clipsToBounds = true
        logo.backgroundColor = Theme.inkRaised
        name.font = Theme.sans(.caption2, weight: .medium)
        name.textColor = Theme.muted
        name.textAlignment = .center
        name.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [logo, name])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 52), logo.heightAnchor.constraint(equalToConstant: 52),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
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
        name.textColor = mine ? accent : Theme.muted
        accessibilityLabel = provider.providerName + (mine ? ", one of your services" : "")
    }
}

final class ChipCell: UICollectionViewCell {
    private let label = UILabel()
    var accent = Theme.amber

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = Theme.mono(.footnote, weight: .bold)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        contentView.addSubview(label)
        label.pin(to: contentView, inset: 0)
        contentView.layer.cornerRadius = 17
        contentView.layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ text: String, selected: Bool, progress: String?) {
        label.text = "  " + text + (progress.map { " · \($0)" } ?? "") + "  "
        label.textColor = selected ? Theme.ink : Theme.paper
        contentView.backgroundColor = selected ? accent : UIColor(white: 1, alpha: 0.08)
        accessibilityLabel = text + (progress.map { ", \($0) watched" } ?? "")
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}

final class EpisodeCell: UICollectionViewCell {
    let punch = PunchButton()
    var onPunch: (() -> Void)?
    private let still = UIImageView()
    private let number = UILabel()
    private let name = UILabel()
    private let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        still.contentMode = .scaleAspectFill
        still.clipsToBounds = true
        still.layer.cornerRadius = 8
        still.layer.cornerCurve = .continuous
        still.backgroundColor = Theme.inkRaised
        number.font = Theme.mono(.caption1, weight: .bold)
        name.font = Theme.serif(.headline)
        name.textColor = Theme.paper
        name.numberOfLines = 2
        detail.font = Theme.sans(.caption1)
        detail.textColor = Theme.muted
        detail.numberOfLines = 2
        [number, name, detail].forEach { $0.adjustsFontForContentSizeCategory = true }
        let text = UIStackView(arrangedSubviews: [number, name, detail])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [still, text, punch])
        row.alignment = .center
        row.spacing = 12
        contentView.addSubview(row)
        row.pin(to: contentView, inset: 0)
        NSLayoutConstraint.activate([
            still.widthAnchor.constraint(equalToConstant: 112),
            still.heightAnchor.constraint(equalToConstant: 63),
        ])
        punch.addAction(UIAction { [weak self] _ in self?.onPunch?() }, for: .primaryActionTriggered)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ episode: Episode, watched: Bool, aired: Bool, accent: UIColor) {
        still.setImage(TMDB.imageURL(episode.stillPath, .still))
        number.text = "E\(episode.episodeNumber)" + (episode.runtime.map { " · \($0)m" } ?? "")
        number.textColor = accent
        name.text = episode.name
        if aired {
            detail.text = episode.overview
        } else {
            detail.text = episode.airDate.flatMap(DateText.pretty).map { "Airs \($0)" } ?? "Not aired yet"
        }
        punch.accent = accent
        punch.set(watched, animated: false)
        punch.isEnabled = aired
        punch.alpha = aired ? 1 : 0.3
        punch.accessibilityLabel = "Episode \(episode.episodeNumber), \(episode.name)"
        contentView.alpha = aired ? 1 : 0.6
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
