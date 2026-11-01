import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thunk() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9) }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum TicketShape {
    /// Rounded ticket outline with semicircle notches on the left and right edges.
    /// `notchAt` places the notches as a fraction of height (0.5 = middle).
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

    /// A vertical dotted perforation line at `x`.
    static func perforation(x: CGFloat, in r: CGRect, inset: CGFloat = 10) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: r.minY + inset))
        path.addLine(to: CGPoint(x: x, y: r.maxY - inset))
        layer.path = path.cgPath
        layer.lineWidth = 2
        layer.lineCap = .round
        layer.lineDashPattern = [0.1, 7]
        layer.fillColor = nil
        return layer
    }
}

/// Animated film grain. Sits behind content, so text stays crisp; static under Reduce Motion.
final class GrainView: UIView {
    private static let noise: UIImage = {
        let size = 160
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }())
        return renderer.image { ctx in
            var rng = SystemRandomNumberGenerator()
            for y in 0..<size { for x in 0..<size {
                let v = CGFloat(UInt8.random(in: 0...255, using: &rng)) / 255
                UIColor(white: v, alpha: CGFloat.random(in: 0...0.5, using: &rng)).setFill()
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            } }
        }
    }()

    private let tile = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        alpha = 0.06
        tile.backgroundColor = UIColor(patternImage: Self.noise).cgColor
        layer.addSublayer(tile)
        NotificationCenter.default.addObserver(self, selector: #selector(restart), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.frame = bounds.insetBy(dx: -80, dy: -80)
        restart()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restart()
    }

    @objc private func restart() {
        tile.removeAllAnimations()
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        // Discrete jumps read as grain flicker rather than sliding texture.
        let jitter = CAKeyframeAnimation(keyPath: "transform.translation")
        jitter.values = (0..<8).map { _ in NSValue(cgSize: CGSize(width: .random(in: -60...60), height: .random(in: -60...60))) }
        jitter.calculationMode = .discrete
        jitter.duration = 0.66
        jitter.repeatCount = .infinity
        tile.add(jitter, forKey: "grain")
    }
}

/// Serif section title with an optional mono caption.
final class SectionHeader: UICollectionReusableView {
    static let kind = "section-header"
    let title = UILabel()
    let caption = UILabel()
    /// Optional trailing action, e.g. "Punch all".
    let accessory = UIButton(type: .system)
    var onAccessory: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = Theme.serif(.title2)
        title.textColor = Theme.paper
        title.adjustsFontForContentSizeCategory = true
        caption.font = Theme.mono(.caption2)
        caption.textColor = Theme.amber
        caption.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [caption, title])
        stack.axis = .vertical
        stack.spacing = 2
        accessory.titleLabel?.font = Theme.mono(.caption1, weight: .bold)
        accessory.isHidden = true
        accessory.addAction(UIAction { [weak self] _ in self?.onAccessory?() }, for: .primaryActionTriggered)
        let row = UIStackView(arrangedSubviews: [stack, accessory])
        row.alignment = .lastBaseline
        addSubview(row)
        row.pin(to: self)
        title.accessibilityTraits = .header
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ text: String, caption: String? = nil, accessory: String? = nil, action: (() -> Void)? = nil) {
        title.text = text
        self.caption.text = caption?.uppercased()
        self.caption.isHidden = caption == nil
        self.accessory.setTitle(accessory?.uppercased(), for: .normal)
        self.accessory.isHidden = accessory == nil
        onAccessory = action
    }
}

/// Poster with a springy press state and optional status badge.
final class PosterCell: UICollectionViewCell {
    let imageView = UIImageView()
    private let badge = UIImageView()
    private let fallback = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        imageView.layer.borderWidth = 0.5
        imageView.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        imageView.backgroundColor = Theme.inkRaised
        contentView.addSubview(imageView)
        imageView.pin(to: contentView)

        fallback.font = Theme.serif(.footnote)
        fallback.textColor = Theme.muted
        fallback.numberOfLines = 4
        fallback.textAlignment = .center
        imageView.addSubview(fallback)
        fallback.pin(to: imageView, inset: 8)

        badge.tintColor = Theme.ink
        badge.backgroundColor = Theme.amber
        badge.contentMode = .center
        badge.preferredSymbolConfiguration = .init(pointSize: 11, weight: .bold)
        badge.layer.cornerRadius = 11
        badge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: Title) {
        imageView.setImage(TMDB.imageURL(title.posterPath, .poster))
        fallback.text = title.posterPath == nil ? title.name : nil
        let status = Store.shared.tracked(title.id, title.mediaType)?.status
        badge.image = status.map { UIImage(systemName: $0.symbol) } ?? nil
        badge.isHidden = status == nil
        accessibilityLabel = [title.name, title.year, status?.label].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }
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
    /// Ink background with grain, shared by every main screen.
    func installBackdrop() {
        view.backgroundColor = Theme.ink
        let grain = GrainView()
        view.insertSubview(grain, at: 0)
        grain.pin(to: view)
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

/// Fixed-size poster grid / row helpers for compositional layouts.
enum Layouts {
    static func posterRow(width: CGFloat = 120, header: Bool = true) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(width), heightDimension: .absolute(width * 1.5)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = 12
        section.contentInsets = .init(top: 10, leading: 20, bottom: 28, trailing: 20)
        if header { section.boundarySupplementaryItems = [headerItem()] }
        return section
    }

    static func posterGrid(columns: Int = 3) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)), heightDimension: .fractionalHeight(1)))
        item.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(1.5 / CGFloat(columns))), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 8, leading: 14, bottom: 24, trailing: 14)
        return section
    }

    static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)), elementKind: SectionHeader.kind, alignment: .top)
        return header
    }
}
