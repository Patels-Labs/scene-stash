import UIKit

/// The pieces every v2 screen is built from: shelves of posters and wide cards, the hero at the top of a
/// page, and the white and glass buttons. Stock UIKit throughout so iOS supplies the Apple TV app's metrics.
enum Shelf {
    static let margin: CGFloat = 20
    static let gap: CGFloat = 10
    static let poster = CGSize(width: 106, height: 159)
    static let wide = CGSize(width: 251, height: 141)
    private static let captionLine: CGFloat = 18

    static func posters(captions: Int = 0) -> NSCollectionLayoutSection {
        row(width: poster.width, height: poster.height + extra(captions))
    }

    static func wides(captions: Int = 0) -> NSCollectionLayoutSection {
        row(width: wide.width, height: wide.height + extra(captions))
    }

    /// People: a circle with a name and a line under it.
    static func circles() -> NSCollectionLayoutSection {
        row(width: poster.width, height: poster.width + extra(2))
    }

    /// One full-width card, for the thing that matters most in a section.
    static func feature(height: CGFloat) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: margin, bottom: 32, trailing: margin)
        section.boundarySupplementaryItems = [header()]
        return section
    }

    static func header() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(40)),
                                                    elementKind: ShelfHeader.kind, alignment: .top)
    }

    private static func extra(_ captions: Int) -> CGFloat { captions > 0 ? 8 + CGFloat(captions) * captionLine : 0 }

    private static func row(width: CGFloat, height: CGFloat) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(width), heightDimension: .absolute(height)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = gap
        section.contentInsets = .init(top: 0, leading: margin, bottom: 32, trailing: margin)
        section.boundarySupplementaryItems = [header()]
        return section
    }
}

/// "Up Next ›": a shelf's title, tappable when the shelf has somewhere to go.
final class ShelfHeader: UICollectionReusableView {
    static let kind = "shelf-header"
    private let button = UIButton(configuration: .plain())
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.configuration?.contentInsets = .zero
        button.configuration?.imagePlacement = .trailing
        button.configuration?.imagePadding = 5
        button.configuration?.baseForegroundColor = Theme.text
        button.configuration?.preferredSymbolConfigurationForImage = .init(font: Theme.text(.headline, weight: .bold))
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = Theme.text(.title2, weight: .semibold); return a
        }
        button.addAction(UIAction { [weak self] _ in self?.action?() }, for: .primaryActionTriggered)
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        button.accessibilityTraits.insert(.header)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: String, action: (() -> Void)? = nil) {
        button.configuration?.title = title
        button.configuration?.image = action == nil ? nil : UIImage(systemName: "chevron.right")?.withTintColor(Theme.secondary, renderingMode: .alwaysOriginal)
        button.isUserInteractionEnabled = action != nil
        self.action = action
    }
}

/// Artwork with the hairline edge every lockup shares.
final class ArtView: UIImageView {
    let fallback = UILabel.make(Theme.text(.headline, weight: .bold), Theme.text, lines: 3)

    init(radius: CGFloat) {
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        backgroundColor = Theme.surfaceHigh
        fallback.textAlignment = .center
        addSubview(fallback)
        fallback.pin(to: self, inset: 10)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ url: URL?, name: String?) {
        setImage(url)
        fallback.text = url == nil ? name : nil
    }
}

/// Up to two lines under a lockup: a title and a quieter detail, or a tinted one.
final class CaptionStack: UIStackView {
    let first = UILabel.make(Theme.text(.footnote))
    let second = UILabel.make(Theme.text(.caption1), Theme.secondary)

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 1
        addArrangedSubview(first)
        addArrangedSubview(second)
    }
    required init(coder: NSCoder) { fatalError() }

    func set(_ a: String?, _ b: String?, tint: UIColor? = nil) {
        first.text = a
        second.text = b
        second.textColor = tint ?? Theme.secondary
        first.isHidden = a == nil
        second.isHidden = b == nil
    }
}

/// A 2:3 poster with optional captions underneath.
final class PosterLockup: UICollectionViewCell {
    let art = ArtView(radius: 10)
    let captions = CaptionStack()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [art, captions])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 1.5),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: Title, caption: String? = nil, detail: String? = nil, tint: UIColor? = nil) {
        art.show(TMDB.imageURL(title.posterPath, .poster), name: title.name)
        captions.set(caption, detail, tint: tint)
        captions.isHidden = caption == nil && detail == nil
        accessibilityLabel = [title.name, caption, detail].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.96) } }
}

/// A 16:9 card: backdrop, a title on the art, a line of detail with an optional progress bar,
/// an optional glass badge, and optional captions underneath.
final class WideLockup: UICollectionViewCell {
    struct Model {
        var backdrop: URL?
        var title: String
        var meta: String? = nil
        var progress: Double? = nil
        var badge: String? = nil
        var caption: String? = nil
        var detail: String? = nil
        var accessibility: String? = nil
    }

    let art = ArtView(radius: 12)
    private let shade = CAGradientLayer()
    private let name = UILabel.make(Theme.text(.title3, weight: .bold), Theme.text, lines: 2)
    private let meta = UILabel.make(Theme.text(.footnote), UIColor(white: 1, alpha: 0.85))
    private let track = UIView()
    private let fill = UIView()
    private var fillWidth: NSLayoutConstraint!
    private let badge = GlassLabel()
    private let captions = CaptionStack()

    override init(frame: CGRect) {
        super.init(frame: frame)
        shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.78).cgColor]
        shade.locations = [0.35, 1]
        art.layer.addSublayer(shade)
        track.backgroundColor = UIColor(white: 1, alpha: 0.3)
        track.layer.cornerRadius = 1.5
        fill.backgroundColor = .white
        fill.layer.cornerRadius = 1.5
        track.addSubview(fill)
        let line = UIStackView(arrangedSubviews: [meta, track])
        line.spacing = 8
        line.alignment = .center
        meta.setContentHuggingPriority(.required, for: .horizontal)
        meta.setContentCompressionResistancePriority(.required, for: .horizontal)
        let onArt = UIStackView(arrangedSubviews: [name, line])
        onArt.axis = .vertical
        onArt.spacing = 4
        [onArt, badge].forEach { art.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        let stack = UIStackView(arrangedSubviews: [art, captions])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fill.translatesAutoresizingMaskIntoConstraints = false
        fillWidth = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 9.0 / 16),
            onArt.leadingAnchor.constraint(equalTo: art.leadingAnchor, constant: 14),
            onArt.trailingAnchor.constraint(equalTo: art.trailingAnchor, constant: -14),
            onArt.bottomAnchor.constraint(equalTo: art.bottomAnchor, constant: -11),
            badge.topAnchor.constraint(equalTo: art.topAnchor, constant: 10),
            badge.leadingAnchor.constraint(equalTo: art.leadingAnchor, constant: 10),
            track.heightAnchor.constraint(equalToConstant: 3),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidth,
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = art.bounds
    }

    func configure(_ m: Model) {
        art.show(m.backdrop, name: nil)
        name.text = m.title
        meta.text = m.meta
        meta.isHidden = m.meta == nil
        track.isHidden = m.progress == nil
        fillWidth.isActive = false
        fillWidth = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: min(max(m.progress ?? 0, 0), 1))
        fillWidth.isActive = true
        badge.text = m.badge
        badge.isHidden = m.badge == nil
        captions.set(m.caption, m.detail)
        captions.isHidden = m.caption == nil && m.detail == nil
        accessibilityLabel = m.accessibility ?? [m.title, m.meta, m.caption, m.detail].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.97) } }
}

/// A person: a round photo (or their initial) with a name and a line under it.
final class CircleLockup: UICollectionViewCell {
    let photo = ArtView(radius: Shelf.poster.width / 2)
    private let captions = CaptionStack()

    override init(frame: CGRect) {
        super.init(frame: frame)
        photo.fallback.font = Theme.text(.largeTitle, weight: .bold)
        captions.first.textAlignment = .center
        captions.second.textAlignment = .center
        captions.first.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [photo, captions])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            photo.heightAnchor.constraint(equalTo: photo.widthAnchor),
        ])
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(photo url: URL?, initial: String? = nil, color: UIColor? = nil, name: String, detail: String?) {
        photo.show(url, name: initial)
        photo.backgroundColor = color ?? Theme.surfaceHigh
        photo.fallback.textColor = color == nil ? Theme.text : .black
        captions.set(name, detail)
        accessibilityLabel = [name, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A small frosted label, for a status on top of artwork.
final class GlassLabel: UIView {
    private let label = UILabel.make(Theme.text(.caption1, weight: .semibold))
    var text: String? { get { label.text } set { label.text = newValue } }

    init() {
        super.init(frame: .zero)
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.layer.cornerRadius = 13
        glass.clipsToBounds = true
        addSubview(glass)
        glass.pin(to: self)
        glass.contentView.addSubview(label)
        label.pin(to: glass.contentView, inset: 0)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -10),
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The two button styles of a v2 page: the white capsule for the main thing, glass for the rest.
enum CapsuleButton {
    static func primary(_ title: String, image: String? = nil) -> UIButton {
        var c = UIButton.Configuration.filled()
        c.baseBackgroundColor = .white
        c.baseForegroundColor = .black
        c.cornerStyle = .capsule
        style(&c, title: title, image: image)
        return sized(UIButton(configuration: c))
    }

    static func glass(_ title: String, image: String? = nil) -> UIButton {
        var c = UIButton.Configuration.glass()
        c.baseForegroundColor = .white
        style(&c, title: title, image: image)
        return sized(UIButton(configuration: c))
    }

    /// Icon only, round.
    static func circle(_ image: String, label: String) -> UIButton {
        var c = UIButton.Configuration.glass()
        c.image = UIImage(systemName: image)
        c.baseForegroundColor = .white
        c.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .semibold)
        let b = UIButton(configuration: c)
        b.accessibilityLabel = label
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 44), b.heightAnchor.constraint(equalToConstant: 44)])
        return b
    }

    private static func style(_ c: inout UIButton.Configuration, title: String, image: String?) {
        c.title = title
        c.image = image.flatMap { UIImage(systemName: $0) }
        c.imagePadding = 8
        c.preferredSymbolConfigurationForImage = .init(pointSize: 15, weight: .semibold)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = Theme.text(.body, weight: .semibold); return a
        }
    }

    private static func sized(_ b: UIButton) -> UIButton {
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return b
    }
}

/// The top of a title's page, or of Tonight: tall artwork fading to black, the title's logo (or its name),
/// a line of detail, and the buttons. The caller fills the button rows and anything below.
final class HeroView: UIView {
    let art = UIImageView()
    let logo = UIImageView()
    let name = UILabel.make(Theme.text(.largeTitle, weight: .heavy), Theme.text, lines: 3)
    let meta = UILabel.make(Theme.text(.subheadline), UIColor(white: 1, alpha: 0.8), lines: 2)
    /// Buttons and text go here, centred over the bottom of the art.
    let content = UIStackView()
    private let shade = CAGradientLayer()
    private var logoTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        art.contentMode = .scaleAspectFill
        art.clipsToBounds = true
        art.backgroundColor = Theme.surface
        shade.colors = [UIColor(white: 0, alpha: 0.35), .clear, .clear, UIColor(white: 0, alpha: 0.85), .black].map(\.cgColor)
        shade.locations = [0, 0.18, 0.45, 0.8, 1]
        art.layer.addSublayer(shade)
        logo.contentMode = .scaleAspectFit
        logo.isHidden = true
        name.textAlignment = .center
        meta.textAlignment = .center
        name.accessibilityTraits = .header
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 12
        [logo, name, meta].forEach(content.addArrangedSubview)
        content.setCustomSpacing(16, after: meta)
        [art, content].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            art.topAnchor.constraint(equalTo: topAnchor),
            art.leadingAnchor.constraint(equalTo: leadingAnchor),
            art.trailingAnchor.constraint(equalTo: trailingAnchor),
            art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 1.5),
            logo.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            logo.heightAnchor.constraint(lessThanOrEqualToConstant: 110),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Shelf.margin),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Shelf.margin),
            // Overlaps the bottom of the art, and pushes the view taller if there's a lot to say.
            content.topAnchor.constraint(greaterThanOrEqualTo: art.bottomAnchor, constant: -250),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            bottomAnchor.constraint(greaterThanOrEqualTo: art.bottomAnchor),
        ])
        let hug = content.topAnchor.constraint(equalTo: art.bottomAnchor, constant: -250)
        hug.priority = .defaultLow
        hug.isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = art.bounds
    }

    /// Shows the art and title; swaps the name for the title's logo once TMDB has one.
    func show(_ title: Title, poster: String? = nil, meta text: String?) {
        art.setImage(TMDB.imageURL(poster ?? title.posterPath, .hero))
        name.text = title.name
        meta.text = text
        meta.isHidden = text == nil
        logoTask?.cancel()
        logoTask = Task { [weak self] in
            guard let path = await TMDB.shared.logo(title.id, title.mediaType), let url = TMDB.imageURL(path, .posterLarge),
                  let image = await ImageLoader.shared.image(url), !Task.isCancelled, let self else { return }
            logo.image = image
            let ratio = image.size.width / max(image.size.height, 1)
            logo.widthAnchor.constraint(equalTo: logo.heightAnchor, multiplier: ratio).isActive = true
            logo.isHidden = false
            name.isHidden = true
            logo.accessibilityLabel = title.name
            logo.isAccessibilityElement = true
        }
    }
}
