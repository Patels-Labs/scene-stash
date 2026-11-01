import UIKit

final class DiscoverViewController: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating {
    nonisolated private enum Section: Hashable { case reel(Int), results }
    /// Titles can appear in several reels, so items carry their section to stay unique.
    nonisolated private struct Item: Hashable { let section: Section; let title: Title }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let search = UISearchController(searchResultsController: nil)
    private var reels: [Int: [Title]] = [:]
    private var results: [Title]?
    private var searchTask: Task<Void, Never>?
    private var searchError: String?
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Discover"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Films, shows…"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        emptyLabel.font = Theme.serif(.title3)
        emptyLabel.textColor = Theme.muted
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
        ])

        configureDataSource()
        loadReels()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    private func loadReels() {
        for (i, reel) in Reel.discover.enumerated() {
            Task {
                guard let titles = try? await TMDB.shared.titles(reel) else { return }
                reels[i] = titles
                applySnapshot()
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchTask?.cancel()
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !text.isEmpty else { results = nil; applySnapshot(); return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await TMDB.shared.search(text)
                guard !Task.isCancelled else { return }
                results = found
                searchError = nil
                applySnapshot()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchError = error.localizedDescription
                applySnapshot()
            }
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .results: Layouts.posterGrid()
            default: Layouts.posterRow()
            }
        }
    }

    private func configureDataSource() {
        let cellReg = UICollectionView.CellRegistration<PosterCell, Item> { cell, _, item in cell.configure(item.title) }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            if case .reel(let i) = dataSource.sectionIdentifier(for: indexPath.section) {
                header.configure(Reel.discover[i].name, caption: "Reel \(i + 1)")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        if let results {
            snap.appendSections([.results])
            snap.appendItems(results.map { Item(section: .results, title: $0) })
            emptyLabel.isHidden = !results.isEmpty
            emptyLabel.text = searchError ?? "Nothing on the marquee for “\(search.searchBar.text ?? "")”."
        } else {
            emptyLabel.isHidden = true
            for i in Reel.discover.indices {
                guard let titles = reels[i], !titles.isEmpty else { continue }
                snap.appendSections([.reel(i)])
                var seen = Set<Title>()
                snap.appendItems(titles.filter { seen.insert($0).inserted }.map { Item(section: .reel(i), title: $0) })
            }
        }
        dataSource.apply(snap, animatingDifferences: false)
    }

    @objc private func storeChanged() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        openDetail(item.title) { [weak self] in
            self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        indexPaths.first.flatMap { dataSource.itemIdentifier(for: $0) }.map { titleMenu($0.title) }
    }
}
