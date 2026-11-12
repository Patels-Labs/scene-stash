import UIKit

/// Search, Apple TV-style: a Trending shelf and portrait Browse tiles until you type, then results as posters.
final class SearchViewController: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating {
    nonisolated private enum Section: Hashable { case trending, browse, results, message }
    nonisolated private enum Item: Hashable { case trending(Title), category(Int), result(Title), message(String) }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let search = UISearchController(searchResultsController: nil)
    private var trending: [Title] = []
    /// Each Browse tile's cover: the first poster in that category.
    private var covers: [Int: Title] = [:]
    private var results: [Title]?
    private var searchTask: Task<Void, Never>?
    private var searchError: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Films, shows and people"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        applySnapshot()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    private func load() {
        Task {
            trending = Array(((try? await TMDB.shared.titles(Reel.featured)) ?? []).prefix(20))
            applySnapshot()
        }
        for (i, reel) in Reel.browse.enumerated() {
            Task {
                guard let first = try? await TMDB.shared.titles(reel).first else { return }
                covers[i] = first
                var snap = dataSource.snapshot()
                if snap.itemIdentifiers.contains(.category(i)) { snap.reconfigureItems([.category(i)]); await dataSource.apply(snap, animatingDifferences: false) }
            }
        }
    }

    @objc private func storeChanged() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers.filter { if case .result = $0 { true } else { false } })
        dataSource.apply(snap, animatingDifferences: false)
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchTask?.cancel()
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !text.isEmpty else {
            results = nil
            applySnapshot()
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await TMDB.shared.search(text)
                guard !Task.isCancelled else { return }
                results = found
                searchError = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchError = error.localizedDescription
            }
            applySnapshot()
        }
    }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .trending: return Shelf.posters()
            case .browse: return Self.grid(captions: false, header: true)
            case .results: return Self.grid(captions: true, header: false)
            case .message, nil:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(80))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 24, leading: Shelf.margin, bottom: 24, trailing: Shelf.margin)
                return s
            }
        }
    }

    /// Three posters across, the way the TV app lays out Browse.
    @MainActor static func grid(captions: Bool, header: Bool) -> NSCollectionLayoutSection {
        let height: NSCollectionLayoutDimension = captions ? .estimated(220) : .fractionalWidth(0.5)
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / 3), heightDimension: height))
        item.contentInsets = .init(top: 0, leading: Shelf.gap / 2, bottom: 0, trailing: Shelf.gap / 2)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: height), subitems: [item])
        let s = NSCollectionLayoutSection(group: group)
        s.interGroupSpacing = captions ? 16 : Shelf.gap
        s.contentInsets = .init(top: 0, leading: Shelf.margin - Shelf.gap / 2, bottom: 32, trailing: Shelf.margin - Shelf.gap / 2)
        if header {
            let h = Shelf.header()
            h.contentInsets = .init(top: 0, leading: Shelf.gap / 2, bottom: 0, trailing: Shelf.gap / 2)
            s.boundarySupplementaryItems = [h]
        }
        return s
    }

    private func configureDataSource() {
        let posterReg = UICollectionView.CellRegistration<PosterLockup, Item> { cell, _, item in
            switch item {
            case .trending(let t): cell.configure(t)
            case .result(let t):
                let kind = t.mediaType == .movie ? "Film" : "TV Show"
                cell.configure(t, caption: t.name, detail: [t.year, kind].compactMap { $0 }.joined(separator: " · "))
            default: break
            }
        }
        let tileReg = UICollectionView.CellRegistration<CategoryTile, Item> { [weak self] cell, _, item in
            guard case .category(let i) = item else { return }
            cell.configure(Reel.browse[i].name, poster: self?.covers[i]?.posterPath)
        }
        let messageReg = UICollectionView.CellRegistration<EmptyCell, Item> { cell, _, item in
            if case .message(let text) = item { cell.configure(nil, text) }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [weak self] header, _, indexPath in
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .trending: header.configure("Trending") { [weak self] in self?.open(Reel.featured) }
            default: header.configure("Browse")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .category: cv.dequeueConfiguredReusableCell(using: tileReg, for: indexPath, item: item)
            case .message: cv.dequeueConfiguredReusableCell(using: messageReg, for: indexPath, item: item)
            case .trending, .result: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, kind, indexPath in
            kind == ShelfHeader.kind ? cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) : nil
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        if let results {
            if results.isEmpty {
                snap.appendSections([.message])
                snap.appendItems([.message(searchError ?? "No films or shows match that. Try a shorter search.")])
            } else {
                snap.appendSections([.results]); snap.appendItems(results.map(Item.result))
            }
        } else {
            if !trending.isEmpty { snap.appendSections([.trending]); snap.appendItems(trending.map(Item.trending)) }
            snap.appendSections([.browse]); snap.appendItems(Reel.browse.indices.map(Item.category))
        }
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func open(_ reel: Reel) {
        navigationController?.pushViewController(ReelViewController(reel: reel), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .trending(let t), .result(let t):
            search.searchBar.resignFirstResponder()
            Haptics.tap()
            openDetail(t) { [weak self] in self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) } }
        case .category(let i): Haptics.tap(); open(Reel.browse[i])
        case .message: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        switch indexPaths.first.flatMap({ dataSource.itemIdentifier(for: $0) }) {
        case .trending(let t), .result(let t): titleMenu(t)
        default: nil
        }
    }
}

/// A Browse tile: a category's poster under a wash of black, with its name at the bottom.
final class CategoryTile: UICollectionViewCell {
    private let art = ArtView(radius: 10)
    private let shade = CAGradientLayer()
    private let name = UILabel.make(Theme.text(.subheadline, weight: .bold), Theme.text, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(art)
        art.pin(to: contentView)
        shade.colors = [UIColor(white: 0, alpha: 0.15).cgColor, UIColor(white: 0, alpha: 0.85).cgColor]
        shade.locations = [0.3, 1]
        art.layer.addSublayer(shade)
        name.textAlignment = .center
        art.addSubview(name)
        name.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: art.leadingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: art.trailingAnchor, constant: -8),
            name.bottomAnchor.constraint(equalTo: art.bottomAnchor, constant: -12),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.frame = art.bounds
    }

    func configure(_ title: String, poster: String?) {
        art.show(TMDB.imageURL(poster, .poster), name: nil)
        name.text = title
        accessibilityLabel = title
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.96) } }
}

/// Everything in one Browse category, as a grid.
final class ReelViewController: UIViewController, UICollectionViewDelegate {
    private let reel: Reel
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout { _, _ in
        SearchViewController.grid(captions: true, header: false)
    })
    private var dataSource: UICollectionViewDiffableDataSource<Int, Title>!

    init(reel: Reel) {
        self.reel = reel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = reel.name
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        let reg = UICollectionView.CellRegistration<PosterLockup, Title> { cell, _, t in
            cell.configure(t, caption: t.name, detail: t.year)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, t in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: t)
        }
        Task {
            let titles = (try? await TMDB.shared.titles(reel)) ?? []
            var snap = NSDiffableDataSourceSnapshot<Int, Title>()
            snap.appendSections([0])
            var seen = Set<Title>()
            snap.appendItems(titles.filter { seen.insert($0).inserted })
            await dataSource.apply(snap)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let t = dataSource.itemIdentifier(for: indexPath) else { return }
        openDetail(t) { [weak self] in self?.dataSource.indexPath(for: t).flatMap { self?.collectionView.cellForItem(at: $0) } }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        indexPaths.first.flatMap { dataSource.itemIdentifier(for: $0) }.map(titleMenu)
    }
}
