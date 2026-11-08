import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thunk() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9) }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum TicketShape {
    /// Rounded ticket outline with semicircle notches on the left and right edges.
    static func path(in r: CGRect, corner: CGFloat = 14, notch: CGFloat = 10, notchAt: CGFloat = 0.5) -> UIBezierPath {
        let p = UIBezierPath()
        let ny = r.minY + r.height * notchAt
        p.move(to: CGPoint(x: r.minX + corner, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
        p.addArc(withCenter: CGPoint(x: r.maxX - corner, y: r.minY + corner), radius: corner, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: ny - notch))
        p.addArc(withCenter: CGPoint(x: r.maxX, y: ny), radius: notch, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - corner))
        p.addArc(withCenter: CGPoint(x: r.maxX - corner, y: r.maxY - corner), radius: corner, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX + corner, y: r.maxY))
        p.addArc(withCenter: CGPoint(x: r.minX + corner, y: r.maxY - corner), radius: corner, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: ny + notch))
        p.addArc(withCenter: CGPoint(x: r.minX, y: ny), radius: notch, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + corner))
        p.addArc(withCenter: CGPoint(x: r.minX + corner, y: r.minY + corner), radius: corner, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        p.close()
        return p
    }

    /// A vertical dotted perforation line.
    static func perforation() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.lineWidth = 2
        layer.lineCap = .round
        layer.lineDashPattern = [0.1, 7]
        layer.fillColor = nil
        return layer
    }
}

/// Section title: a tracked caption over a bold title, with an optional trailing action.
final class SectionHeader: UICollectionReusableView {
    static let kind = "section-header"
    let title = UILabel.make(Theme.text(.title2, weight: .bold))
    let caption = UILabel.make(Theme.label(), Theme.tertiary)
    let accessory = UIButton(type: .system)
    var onAccessory: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [caption, title])
        stack.axis = .vertical
        stack.spacing = 3
        accessory.titleLabel?.font = Theme.label(.caption1, weight: .bold)
        accessory.tintColor = Theme.accent
        accessory.isHidden = true
        accessory.addAction(UIAction { [weak self] _ in self?.onAccessory?() }, for: .primaryActionTriggered)
        accessory.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [stack, accessory])
        row.alignment = .lastBaseline
        addSubview(row)
        row.pin(to: self)
        title.accessibilityTraits = .header
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ text: String, caption: String? = nil, accessory: String? = nil, action: (() -> Void)? = nil) {
        title.text = text
        self.caption.setCaps(caption)
        self.caption.isHidden = caption == nil
        self.accessory.setTitle(accessory?.uppercased(), for: .normal)
        self.accessory.isHidden = accessory == nil
        onAccessory = action
    }
}

/// Poster thumbnail with a printed-card edge, springy press and status badge.
final class PosterCell: UICollectionViewCell {
    let imageView = UIImageView()
    private let badge = UIImageView()
    private let fallback = UILabel.make(Theme.display(20), Theme.secondary, lines: 4)

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        imageView.backgroundColor = Theme.surface
        contentView.addSubview(imageView)
        imageView.pin(to: contentView)

        fallback.textAlignment = .center
        imageView.addSubview(fallback)
        fallback.pin(to: imageView, inset: 10)

        badge.tintColor = .black
        badge.backgroundColor = Theme.accent
        badge.contentMode = .center
        badge.preferredSymbolConfiguration = .init(pointSize: 10, weight: .heavy)
        badge.layer.cornerRadius = 11
        badge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: Title) {
        imageView.setImage(TMDB.imageURL(title.posterPath, .poster))
        fallback.text = title.posterPath == nil ? title.name.uppercased() : nil
        let status = Store.shared.tracked(title.id, title.mediaType)?.status
        badge.image = status.map { UIImage(systemName: $0.symbol) } ?? nil
        badge.isHidden = status == nil
        accessibilityLabel = [title.name, title.year, status?.label].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool {
        didSet { Spring.press(self, isHighlighted, scale: 0.95) }
    }
}

enum Spring {
    static func press(_ view: UIView, _ down: Bool, scale: CGFloat = 0.96) {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            view.transform = down ? CGAffineTransform(scaleX: scale, y: scale) : .identity
        }
    }
}

/// White capsule call to action, the one primary button style in the app.
final class PillButton: UIButton {
    convenience init(_ title: String, image: String? = nil, inverted: Bool = false) {
        self.init(configuration: .filled())
        configuration?.title = title
        configuration?.image = image.flatMap { UIImage(systemName: $0) }
        configuration?.imagePadding = 8
        configuration?.cornerStyle = .capsule
        configuration?.buttonSize = .large
        configuration?.baseBackgroundColor = inverted ? Theme.surfaceHigh : .white
        configuration?.baseForegroundColor = inverted ? .white : .black
        configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = Theme.text(.headline, weight: .semibold); return a
        }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted) } }
}

extension UIView {
    func pin(to other: UIView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: other.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset),
        ])
    }
}

extension UIViewController {
    func installBackdrop() {
        view.backgroundColor = Theme.bg
    }

    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't load", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Opens a title's detail with the native zoom transition from `source`.
    func openDetail(_ title: Title, from source: @escaping () -> UIView?) {
        let detail = DetailViewController(title: title)
        detail.preferredTransition = .zoom { _ in source() }
        navigationController?.pushViewController(detail, animated: true)
    }

    /// Long-press menu shared by every poster.
    func titleMenu(_ title: Title) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let current = Store.shared.tracked(title.id, title.mediaType)?.status
            var actions: [UIMenuElement] = TrackStatus.allCases.map { status in
                UIAction(title: status.label, image: UIImage(systemName: status.symbol), state: current == status ? .on : .off) { _ in
                    Store.shared.track(title, status: status)
                    Haptics.success()
                }
            }
            if current != nil {
                actions.append(UIAction(title: "Remove from Stash", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    Store.shared.remove(title)
                })
            }
            return UIMenu(title: title.name, children: actions)
        }
    }
}

enum Layouts {
    static func posterRow(width: CGFloat = 116, header: Bool = true) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(width), heightDimension: .absolute(width * 1.5)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = 10
        section.contentInsets = .init(top: 12, leading: 20, bottom: 36, trailing: 20)
        if header { section.boundarySupplementaryItems = [headerItem()] }
        return section
    }

    static func posterGrid(columns: Int = 3) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)), heightDimension: .fractionalHeight(1)))
        item.contentInsets = .init(top: 5, leading: 5, bottom: 5, trailing: 5)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(1.5 / CGFloat(columns))), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 8, leading: 15, bottom: 24, trailing: 15)
        return section
    }

    static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(48)), elementKind: SectionHeader.kind, alignment: .top)
    }
}

/// A plain view that reports its layout, for layers that follow its size.
final class CardView: UIView {
    var onLayout: ((CGRect) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(bounds) }
}
