import CoreData
import UIKit

extension NightStatus {
    var tint: UIColor {
        switch self {
        case .noTickets: Theme.secondary
        case .ticketsInHand: UIColor(red: 0.56, green: 0.83, blue: 0.86, alpha: 1)
        case .lightsDown, .creditsRolled: Theme.accent
        }
    }
}

/// Nights out with friends: what's coming up as ticket stubs, and the scrapbook of nights gone by.
final class NightsViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case upcoming, scrapbook }
    /// Separate cases per section: when the credits roll a night moves from stub to poster, and reconfiguring
    /// one identifier across cell types crashes.
    nonisolated private enum Item: Hashable { case upcoming(NSManagedObjectID), past(NSManagedObjectID), empty }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var clock: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        title = "Movie Nights"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Plan a night", image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.plan() })
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Store.shared.updateFromNights()
        reload()
        // Stages change with the clock, not just with edits.
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in Store.shared.updateFromNights(); self?.reload() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clock?.invalidate()
    }

    /// Off screen it waits: viewWillAppear reloads, and each reload looks up every night's share.
    @objc private func storeChanged() { if view.window != nil { reload() } }

    private func reload() {
        let nights = Store.shared.nights()
        let upcoming = nights.filter { $0.status() != .creditsRolled }
        let past = nights.filter { $0.status() == .creditsRolled }.reversed()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.upcoming])
        snapshot.appendItems(upcoming.isEmpty ? [.empty] : upcoming.map { .upcoming($0.objectID) })
        if !past.isEmpty {
            snapshot.appendSections([.scrapbook])
            snapshot.appendItems(past.map { .past($0.objectID) })
        }
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private func plan() {
        let picker = NightFilmPickerViewController { [weak self] night in self?.open(night) }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func open(_ night: MovieNight) {
        navigationController?.pushViewController(NightViewController(night: night), animated: true)
    }

    private func night(_ id: NSManagedObjectID) -> MovieNight? {
        try? Store.shared.context.existingObject(with: id) as? MovieNight
    }

    // MARK: Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            let section = self?.dataSource?.sectionIdentifier(for: index) ?? .upcoming
            switch section {
            case .upcoming:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(132)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(132)), subitems: [item])
                let s = NSCollectionLayoutSection(group: group)
                s.interGroupSpacing = 12
                s.contentInsets = .init(top: 8, leading: 16, bottom: 32, trailing: 16)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            case .scrapbook:
                let s = Layouts.posterGrid()
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            }
        }
    }

    private func configureDataSource() {
        let stubReg = UICollectionView.CellRegistration<NightStubCell, NSManagedObjectID> { [weak self] cell, _, id in
            if let night = self?.night(id) { cell.configure(night) }
        }
        let posterReg = UICollectionView.CellRegistration<PosterCell, NSManagedObjectID> { [weak self] cell, _, id in
            if let night = self?.night(id) { cell.configure(night.title) }
        }
        let emptyReg = UICollectionView.CellRegistration<EmptyCell, Item> { cell, _, _ in
            cell.configure("Nothing booked", "Plan a night out, invite your friends, and keep the cinema, screen and seats on one ticket.")
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .empty: return cv.dequeueConfiguredReusableCell(using: emptyReg, for: indexPath, item: item)
            case .upcoming(let id): return cv.dequeueConfiguredReusableCell(using: stubReg, for: indexPath, item: id)
            case .past(let id): return cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: id)
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [weak self] header, _, indexPath in
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .scrapbook: header.configure("The Scrapbook", caption: "Nights gone by")
            default: header.configure("Coming up", caption: "With friends")
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .empty
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .upcoming(let id), .past(let id): if let night = night(id) { open(night) }
        default: break
        }
    }
}

/// A night as a ticket stub: poster, what and where, who's going, and the date torn off on the right.
final class NightStubCell: UICollectionViewCell {
    private let poster = UIImageView()
    private let status = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let name = UILabel.make(Theme.display(26, weight: .black), Theme.text, lines: 2)
    private let place = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 2)
    private let crew = UIStackView()
    private let month = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)
    private let day = UILabel.make(Theme.display(36, weight: .black))
    private let time = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)
    private let card = CAShapeLayer()
    private let perforation = TicketShape.perforation()
    private let stub = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.addSublayer(card)
        card.lineWidth = 1.5
        card.lineDashPattern = [5, 4]

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 8
        poster.backgroundColor = Theme.surface
        poster.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([poster.widthAnchor.constraint(equalToConstant: 62), poster.heightAnchor.constraint(equalToConstant: 93)])
        // Keeps the poster its own size at the top instead of stretching (or stretching the card) to match.
        let posterColumn = UIStackView(arrangedSubviews: [poster, UIView()])
        posterColumn.axis = .vertical

        crew.spacing = -6
        let main = UIStackView(arrangedSubviews: [status, name, place, crew])
        main.axis = .vertical
        main.spacing = 5
        main.setCustomSpacing(10, after: place)
        main.alignment = .leading

        let date = UIStackView(arrangedSubviews: [month, day, time])
        date.axis = .vertical
        date.alignment = .center
        date.spacing = 4
        stub.addSubview(date)
        date.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            date.centerXAnchor.constraint(equalTo: stub.centerXAnchor), date.centerYAnchor.constraint(equalTo: stub.centerYAnchor),
            stub.widthAnchor.constraint(equalToConstant: 72),
        ])
        contentView.layer.addSublayer(perforation)

        let row = UIStackView(arrangedSubviews: [posterColumn, main, stub])
        row.spacing = 14
        row.alignment = .fill
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 12, trailing: 0)
        contentView.addSubview(row)
        row.pin(to: contentView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.path = TicketShape.path(in: contentView.bounds.insetBy(dx: 0.75, dy: 0.75), corner: 16, notch: 9, notchAt: 0.5).cgPath
        contentView.layoutIfNeeded()
        let x = stub.frame.minX
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: 12))
        path.addLine(to: CGPoint(x: x, y: contentView.bounds.height - 12))
        perforation.path = path.cgPath
    }

    func configure(_ night: MovieNight) {
        let stage = night.status()
        let tint = stage.tint
        poster.setImage(TMDB.imageURL(night.posterPath, .poster))
        status.setCaps(stage.label)
        status.textColor = tint
        name.setDisplay(night.name?.uppercased())
        place.text = night.whereLine ?? "Cinema not picked yet"

        crew.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, guest) in Store.shared.guests(for: night).prefix(6).enumerated() {
            crew.addArrangedSubview(Avatar(guest.initial, index: i, size: 24))
        }

        let showtime = night.showtime ?? .now
        month.setCaps(showtime.formatted(.dateTime.month(.abbreviated)))
        day.text = showtime.formatted(.dateTime.day())
        day.textColor = tint
        time.setCaps(showtime.formatted(date: .omitted, time: .shortened))

        card.fillColor = tint.withAlphaComponent(stage == .noTickets ? 0.05 : 0.12).cgColor
        card.strokeColor = tint.withAlphaComponent(0.5).cgColor
        perforation.strokeColor = tint.withAlphaComponent(0.6).cgColor
        accessibilityLabel = "\(night.name ?? ""), \(stage.label), \(showtime.formatted(date: .abbreviated, time: .shortened)), \(place.text ?? "")"
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.97) } }
}

/// A friend's initial in a coloured disc.
final class Avatar: UILabel {
    static let colors: [UIColor] = [Theme.accent, UIColor(red: 0.56, green: 0.83, blue: 0.86, alpha: 1),
                                    UIColor(red: 0.94, green: 0.64, blue: 0.78, alpha: 1), UIColor(red: 0.73, green: 0.88, blue: 0.56, alpha: 1)]

    convenience init(_ initial: String, index: Int, size: CGFloat) {
        self.init()
        text = initial
        font = .systemFont(ofSize: size * 0.42, weight: .heavy)
        textColor = .black
        textAlignment = .center
        backgroundColor = Self.colors[index % Self.colors.count]
        layer.cornerRadius = size / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor.black.cgColor
        clipsToBounds = true
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
    }
}
