import UIKit

final class StashViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case header, stubs }
    nonisolated private enum Item: Hashable { case header, stub(Title), empty }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let header = UIStackView()
    private let marquee = MarqueeView()
    private let segments = UISegmentedControl(items: TrackStatus.allCases.map(\.label))
    private var status: TrackStatus { TrackStatus.allCases[segments.selectedSegmentIndex] }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stash"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [weak self] _ in
            self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
        })
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Settings"

        segments.selectedSegmentIndex = 1
        segments.selectedSegmentTintColor = Theme.amber
        segments.setTitleTextAttributes([.foregroundColor: Theme.ink, .font: Theme.mono(.footnote, weight: .bold)], for: .selected)
        segments.setTitleTextAttributes([.foregroundColor: Theme.paper, .font: Theme.mono(.footnote, weight: .medium)], for: .normal)
        segments.addAction(UIAction { [weak self] _ in Haptics.tap(); self?.reload(animated: true) }, for: .valueChanged)
        header.axis = .vertical
        header.spacing = 18
        header.addArrangedSubview(marquee)
        header.addArrangedSubview(segments)
        marquee.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        segments.heightAnchor.constraint(equalToConstant: 36).isActive = true

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        // Land on whichever shelf has something on it.
        if Store.shared.all(.watching).isEmpty { segments.selectedSegmentIndex = Store.shared.all(.watchlist).isEmpty ? 2 : 0 }
        reload(animated: false)
    }

    @objc private func storeChanged() { reload(animated: true) }

    private func reload(animated: Bool) {
        let stats = Store.shared.stats()
        marquee.content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hours = stats.minutes / 60
        [MarqueeView.stat(hours >= 1000 ? "\(hours / 1000)k" : "\(hours)", "hours"),
         MarqueeView.stat("\(stats.titles)", "titles"),
         MarqueeView.stat("\(stats.episodes)", "episodes"),
         MarqueeView.stat("\(stats.streak)", "day streak")].forEach(marquee.content.addArrangedSubview)
        for (i, s) in TrackStatus.allCases.enumerated() {
            let count = Store.shared.all(s).count
            segments.setTitle(count > 0 ? "\(s.label) \(count)" : s.label, forSegmentAt: i)
        }

        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.header, .stubs])
        snap.appendItems([.header], toSection: .header)
        let items = Store.shared.all(status).map { Item.stub($0.title) }
        snap.appendItems(items.isEmpty ? [.empty] : items, toSection: .stubs)
        snap.reconfigureItems(snap.itemIdentifiers(inSection: .stubs).filter { dataSource.snapshot().itemIdentifiers.contains($0) })
        dataSource.apply(snap, animatingDifferences: animated && !UIAccessibility.isReduceMotionEnabled)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { index, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(index == 0 ? 180 : 132))
            let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
            section.interGroupSpacing = 14
            section.contentInsets = .init(top: index == 0 ? 8 : 0, leading: 20, bottom: index == 0 ? 22 : 30, trailing: 20)
            return section
        }
    }

    private func configureDataSource() {
        let hostReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(header) }
        let stubReg = UICollectionView.CellRegistration<StubCell, Item> { cell, _, item in
            if case .stub(let t) = item { cell.configure(t) }
        }
        let emptyReg = UICollectionView.CellRegistration<EmptyCell, Item> { [unowned self] cell, _, _ in
            switch status {
            case .watchlist: cell.configure("Nothing stashed yet", "Find something in Discover and tear off a ticket.")
            case .watching: cell.configure("No shows on the go", "Punch an episode of any show to start tracking it.")
            case .seen: cell.configure("Your ticket box is empty", "Mark films and shows as seen to fill it up.")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .header: cv.dequeueConfiguredReusableCell(using: hostReg, for: indexPath, item: item)
            case .stub: cv.dequeueConfiguredReusableCell(using: stubReg, for: indexPath, item: item)
            case .empty: cv.dequeueConfiguredReusableCell(using: emptyReg, for: indexPath, item: item)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .stub = dataSource.itemIdentifier(for: indexPath) { return true }
        return false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .stub(let t) = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        openDetail(t) { [weak self] in
            self?.dataSource.indexPath(for: .stub(t)).flatMap { (collectionView.cellForItem(at: $0) as? StubCell)?.poster }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .stub(let t) = dataSource.itemIdentifier(for: ip) else { return nil }
        return titleMenu(t)
    }
}

/// A library entry drawn as a ticket stub: poster, title, then a torn-off stub with the rating or progress.
final class StubCell: UICollectionViewCell {
    let poster = UIImageView()
    private let shape = CAShapeLayer()
    private let perforation = TicketShape.perforation(x: 0, in: .zero)
    private let kicker = UILabel()
    private let name = UILabel()
    private let detail = UILabel()
    private let stubValue = UILabel()
    private let stubCaption = UILabel()
    private let stubWidth: CGFloat = 76

    override init(frame: CGRect) {
        super.init(frame: frame)
        shape.fillColor = Theme.inkRaised.cgColor
        shape.strokeColor = UIColor(white: 1, alpha: 0.08).cgColor
        shape.lineWidth = 1
        contentView.layer.addSublayer(shape)
        perforation.strokeColor = UIColor(white: 1, alpha: 0.25).cgColor
        contentView.layer.addSublayer(perforation)

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 6
        poster.layer.cornerCurve = .continuous
        poster.backgroundColor = Theme.ink
        kicker.font = Theme.mono(.caption2, weight: .bold)
        kicker.textColor = Theme.amber
        name.font = Theme.serif(.title3)
        name.textColor = Theme.paper
        name.numberOfLines = 2
        detail.font = Theme.mono(.caption1, weight: .medium)
        detail.textColor = Theme.muted
        detail.numberOfLines = 2
        stubValue.font = Theme.serif(.title1, weight: .heavy)
        stubValue.textColor = Theme.amber
        stubValue.textAlignment = .center
        stubValue.adjustsFontSizeToFitWidth = true
        stubCaption.font = Theme.mono(.caption2, weight: .bold)
        stubCaption.textColor = Theme.muted
        stubCaption.textAlignment = .center
        stubCaption.numberOfLines = 2
        [kicker, name, detail, stubValue, stubCaption].forEach { $0.adjustsFontForContentSizeCategory = true }

        let text = UIStackView(arrangedSubviews: [kicker, name, detail])
        text.axis = .vertical
        text.spacing = 4
        let stub = UIStackView(arrangedSubviews: [stubValue, stubCaption])
        stub.axis = .vertical
        stub.spacing = 0
        let row = UIStackView(arrangedSubviews: [poster, text, stub])
        row.alignment = .center
        row.spacing = 14
        row.setCustomSpacing(18, after: text)
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            poster.widthAnchor.constraint(equalToConstant: 66),
            poster.heightAnchor.constraint(equalToConstant: 99),
            stub.widthAnchor.constraint(equalToConstant: stubWidth - 18),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -9),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.path = TicketShape.path(in: contentView.bounds, corner: 14, notch: 11).cgPath
        let x = contentView.bounds.maxX - stubWidth
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x, y: 12)); p.addLine(to: CGPoint(x: x, y: contentView.bounds.maxY - 12))
        perforation.path = p.cgPath
    }

    func configure(_ title: Title) {
        poster.setImage(TMDB.imageURL(title.posterPath, .poster))
        name.text = title.name
        kicker.text = [title.mediaType == .movie ? "FILM" : "SERIES", title.year].compactMap { $0 }.joined(separator: " · ")
        let tracked = Store.shared.tracked(title.id, title.mediaType)
        switch tracked?.status ?? .watchlist {
        case .watchlist:
            if let date = title.date, !DateText.isPast(date), let pretty = DateText.pretty(date) {
                detail.text = "PREMIERES \(pretty.uppercased())"
                stubValue.text = "SOON"
            } else {
                detail.text = tracked?.addedAt.map { "STASHED " + $0.formatted(.dateTime.month(.abbreviated).day()).uppercased() }
                stubValue.text = "1"
            }
            stubCaption.text = "ADMIT"
        case .watching:
            let eps = Store.shared.episodes(show: title.id)
            let last = eps.map(\.key).max()
            detail.text = last.map { "LAST PUNCHED \($0.label)" } ?? "NOT STARTED"
            stubValue.text = "\(eps.count)"
            stubCaption.text = eps.count == 1 ? "EPISODE" : "EPISODES"
        case .seen:
            detail.text = tracked?.watchedAt.map { "SEEN " + $0.formatted(.dateTime.month(.abbreviated).day().year()).uppercased() }
            let rating = Int(tracked?.rating ?? 0)
            stubValue.text = rating > 0 ? "\(rating)" : "–"
            stubCaption.text = rating > 0 ? "OF 10" : "UNRATED"
        }
        accessibilityLabel = [title.name, kicker.text, detail.text, "\(stubValue.text ?? "") \(stubCaption.text ?? "")"].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97).rotated(by: -0.008) : .identity
            }
        }
    }
}

final class EmptyCell: UICollectionViewCell {
    private let icon = UIImageView(image: UIImage(systemName: "ticket"))
    private let title = UILabel()
    private let body = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = Theme.amber
        icon.preferredSymbolConfiguration = .init(pointSize: 40, weight: .light)
        icon.contentMode = .center
        title.font = Theme.serif(.title2)
        title.textColor = Theme.paper
        body.font = Theme.sans(.subheadline)
        body.textColor = Theme.muted
        [title, body].forEach { $0.textAlignment = .center; $0.numberOfLines = 0; $0.adjustsFontForContentSizeCategory = true }
        let stack = UIStackView(arrangedSubviews: [icon, title, body])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        contentView.addSubview(stack)
        stack.pin(to: contentView, inset: 32)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: String, _ body: String) {
        self.title.text = title
        self.body.text = body
        accessibilityLabel = "\(title). \(body)"
    }
}
