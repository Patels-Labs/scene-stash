import UIKit

/// Your library as shelves: what you're watching, your watchlist, what you've watched, marathons and extras.
final class LibraryViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case stats, watching, watchlist, watched, marathons, extras, empty }
    nonisolated private enum Extra: Hashable { case year, history, alerts }
    nonisolated private enum Item: Hashable {
        case stats, empty
        case watching(Title), watchlist(Title), watched(Title)
        case marathon(String), extra(Extra)
    }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        reload()
    }

    @objc private func storeChanged() { reload() }

    private func reload() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        let all = Store.shared.all()
        if all.isEmpty {
            snap.appendSections([.empty]); snap.appendItems([.empty])
        } else {
            snap.appendSections([.stats]); snap.appendItems([.stats])
        }
        let shelves: [(Section, TrackStatus, (Title) -> Item)] = [(.watching, .watching, Item.watching), (.watchlist, .watchlist, Item.watchlist), (.watched, .seen, Item.watched)]
        for (section, status, item) in shelves {
            let titles = Store.shared.all(status).prefix(20).map(\.title)
            if !titles.isEmpty { snap.appendSections([section]); snap.appendItems(titles.map(item)) }
        }
        let marathons = Store.shared.marathons().compactMap(\.uuid)
        if !marathons.isEmpty { snap.appendSections([.marathons]); snap.appendItems(marathons.map(Item.marathon)) }
        if !all.isEmpty { snap.appendSections([.extras]); snap.appendItems([.extra(.year), .extra(.history), .extra(.alerts)]) }
        snap.reconfigureItems(snap.itemIdentifiers.filter { Set(dataSource.snapshot().itemIdentifiers).contains($0) })
        dataSource.apply(snap, animatingDifferences: view.window != nil && !UIAccessibility.isReduceMotionEnabled)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .watching, .marathons: return Shelf.wides(captions: 2)
            case .extras: return Shelf.wides()
            case .watchlist: return Shelf.posters()
            case .watched: return Shelf.posters(captions: 2)
            case .stats, .empty, nil:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(40))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 0, leading: Shelf.margin, bottom: 24, trailing: Shelf.margin)
                return s
            }
        }
    }

    private func configureDataSource() {
        let statsReg = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, _ in
            let s = Store.shared.stats()
            var c = UIListContentConfiguration.cell()
            c.text = "\(s.minutes / 60) hours · \(s.films) films · \(s.episodes) episodes" + (s.streak > 1 ? " · \(s.streak)-day streak" : "")
            c.textProperties.font = Theme.text(.subheadline)
            c.textProperties.color = Theme.secondary
            c.directionalLayoutMargins = .zero
            cell.contentConfiguration = c
            cell.backgroundConfiguration = .clear()
        }
        let emptyReg = UICollectionView.CellRegistration<EmptyCell, Item> { cell, _, _ in
            cell.configure("Nothing here yet", "Add films and shows from Search, or from Tonight, and they'll collect here.")
        }
        let wideReg = UICollectionView.CellRegistration<WideLockup, Item> { cell, _, item in
            switch item {
            case .watching(let t): cell.configure(Self.watching(t))
            case .marathon(let uuid):
                guard let m = Store.shared.marathons().first(where: { $0.uuid == uuid }) else { return }
                let left = m.remaining
                let next = m.upcomingPlan().first { !$0.slots.isEmpty }?.day.start
                cell.configure(.init(backdrop: TMDB.imageURL(left.first?.backdrop ?? m.pieces.first?.backdrop, .backdrop), title: m.name ?? "Marathon",
                                     caption: next.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) } ?? "Nothing scheduled",
                                     detail: left.isEmpty ? "All watched" : "\(left.count) left · about \(DateText.runtime(left.reduce(0) { $0 + $1.minutes }))"))
            case .extra(let e): cell.configure(Self.extra(e))
            default: break
            }
        }
        let posterReg = UICollectionView.CellRegistration<PosterLockup, Item> { cell, _, item in
            switch item {
            case .watchlist(let t): cell.configure(t)
            case .watched(let t):
                let tracked = Store.shared.tracked(t.id, t.mediaType)
                let rating = Int(tracked?.rating ?? 0)
                cell.configure(t, caption: t.name, detail: rating > 0 ? "Rated \(rating)" : tracked?.watchedAt?.formatted(.dateTime.month(.abbreviated).year()),
                               tint: rating > 0 ? Theme.accent : nil)
            default: break
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .watching: header.configure("Watching") { [weak self] in self?.openList(.watching) }
            case .watchlist: header.configure("Watchlist") { [weak self] in self?.openList(.watchlist) }
            case .watched: header.configure("Watched") { [weak self] in self?.openList(.seen) }
            case .marathons: header.configure("Marathons") { [weak self] in self?.navigationController?.pushViewController(MarathonListViewController(), animated: true) }
            case .extras: header.configure("Extras")
            default: header.configure("")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .stats: cv.dequeueConfiguredReusableCell(using: statsReg, for: indexPath, item: item)
            case .empty: cv.dequeueConfiguredReusableCell(using: emptyReg, for: indexPath, item: item)
            case .watching, .marathon, .extra: cv.dequeueConfiguredReusableCell(using: wideReg, for: indexPath, item: item)
            case .watchlist, .watched: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, kind, indexPath in
            kind == ShelfHeader.kind ? cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) : nil
        }
    }

    /// A film shows how far through you are; a show, how many episodes you've watched.
    private static func watching(_ t: Title) -> WideLockup.Model {
        let tracked = Store.shared.tracked(t.id, t.mediaType)
        if t.mediaType == .movie, let tracked, tracked.runtime > 0 {
            let left = max(Int(tracked.runtime) - Int(tracked.position) / 60, 0)
            return .init(backdrop: TMDB.imageURL(t.backdropPath, .backdrop), title: t.name, meta: "\(DateText.runtime(left)) left",
                         progress: Double(tracked.position) / Double(max(tracked.runtime * 60, 1)), caption: t.name, detail: "Film")
        }
        let count = Store.shared.episodes(show: t.id).count
        return .init(backdrop: TMDB.imageURL(t.backdropPath, .backdrop), title: t.name, caption: t.name,
                     detail: count == 0 ? "Not started" : "\(count) episode\(count == 1 ? "" : "s") watched")
    }

    private static func extra(_ e: Extra) -> WideLockup.Model {
        let recent = Store.shared.all(.seen).first?.title
        switch e {
        case .year:
            let year = Calendar.current.component(.year, from: .now)
            let films = Store.shared.all(.seen).filter { $0.mediaType == .movie && $0.watchedAt.map { Calendar.current.component(.year, from: $0) == year } ?? false }.count
            return .init(backdrop: TMDB.imageURL(recent?.backdropPath, .backdrop), title: "Year in Review", meta: "\(year) so far · \(films) films")
        case .history:
            return .init(backdrop: TMDB.imageURL(Store.shared.all(.seen).dropFirst().first?.backdropPath, .backdrop), title: "History", meta: "Everything you've watched, by date")
        case .alerts:
            let show = Store.shared.all(.watching).first { $0.mediaType == .tv }?.title
            return .init(backdrop: TMDB.imageURL(show?.backdropPath, .backdrop), title: "New Episode Alerts", meta: "The evening a new episode lands")
        }
    }

    private func openList(_ status: TrackStatus) {
        navigationController?.pushViewController(LibraryListViewController(status: status), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .stats, .empty, nil: false
        default: true
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .watching(let t), .watchlist(let t), .watched(let t):
            Haptics.tap()
            openDetail(t) { [weak self] in self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) } }
        case .marathon(let uuid):
            guard let m = Store.shared.marathons().first(where: { $0.uuid == uuid }) else { return }
            withPass { navigationController?.pushViewController(MarathonPlannerViewController(marathon: m), animated: true) }
        case .extra(.year): withPass { present(YearViewController(), animated: true) }
        case .extra(.history): withPass { navigationController?.pushViewController(StubBookViewController(), animated: true) }
        case .extra(.alerts): present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
        case .stats, .empty: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        switch indexPaths.first.flatMap({ dataSource.itemIdentifier(for: $0) }) {
        case .watching(let t), .watchlist(let t), .watched(let t): titleMenu(t)
        default: nil
        }
    }
}

/// Everything on one shelf, as a grid.
final class LibraryListViewController: UIViewController, UICollectionViewDelegate {
    private let status: TrackStatus
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout { _, _ in
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / 3), heightDimension: .estimated(220)))
        item.contentInsets = .init(top: 0, leading: Shelf.gap / 2, bottom: 0, trailing: Shelf.gap / 2)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(220)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 16
        section.contentInsets = .init(top: 8, leading: Shelf.margin - Shelf.gap / 2, bottom: 100, trailing: Shelf.margin - Shelf.gap / 2)
        return section
    })
    private var dataSource: UICollectionViewDiffableDataSource<Int, Title>!

    init(status: TrackStatus) {
        self.status = status
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = status.label
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        let reg = UICollectionView.CellRegistration<PosterLockup, Title> { [status] cell, _, t in
            let tracked = Store.shared.tracked(t.id, t.mediaType)
            let rating = Int(tracked?.rating ?? 0)
            let detail = status == .seen && rating > 0 ? "Rated \(rating)" : t.year
            cell.configure(t, caption: t.name, detail: detail, tint: status == .seen && rating > 0 ? Theme.accent : nil)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, t in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: t)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        reload()
    }

    @objc private func reload() {
        var snap = NSDiffableDataSourceSnapshot<Int, Title>()
        snap.appendSections([0])
        snap.appendItems(Store.shared.all(status).map(\.title))
        dataSource.apply(snap, animatingDifferences: view.window != nil)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let t = dataSource.itemIdentifier(for: indexPath) else { return }
        openDetail(t) { [weak self] in self?.collectionView.cellForItem(at: indexPath) }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        indexPaths.first.flatMap { dataSource.itemIdentifier(for: $0) }.map(titleMenu)
    }
}
