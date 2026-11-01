import UIKit

final class DiscoverViewController: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating {
    nonisolated private enum Section: Hashable { case featured, reel(Int), results }
    /// Titles can appear in several reels, so items carry their section to stay unique.
    nonisolated private struct Item: Hashable { let section: Section; let title: Title }

    private let glow = GlowView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let search = UISearchController(searchResultsController: nil)
    private var featured: [Title] = []
    private var reels: [Int: [Title]] = [:]
    private var results: [Title]?
    private var searchTask: Task<Void, Never>?
    private var searchError: String?
    private var focused = -1
    private let emptyLabel = UILabel.make(Theme.display(30, weight: .black), Theme.secondary, lines: 0)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Discover"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Films, shows, anything"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false

        view.addSubview(glow)
        glow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: view.topAnchor),
            glow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glow.heightAnchor.constraint(equalToConstant: 720),
        ])
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
        ])

        configureDataSource()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    private func load() {
        Task {
            featured = Array(((try? await TMDB.shared.titles(Reel.featured)) ?? []).prefix(10))
            applySnapshot()
            focus(0)
        }
        for (i, reel) in Reel.discover.enumerated() {
            Task {
                guard let titles = try? await TMDB.shared.titles(reel) else { return }
                reels[i] = titles
                applySnapshot()
            }
        }
    }

    private func focus(_ index: Int) {
        guard index != focused, let title = featured[safe: index], results == nil else { return }
        focused = index
        glow.show(TMDB.imageURL(title.posterPath, .poster))
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchTask?.cancel()
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !text.isEmpty else {
            results = nil
            applySnapshot()
            let f = focused; focused = -1; focus(max(f, 0))
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
                applySnapshot()
                glow.show(TMDB.imageURL(found.first?.posterPath, .poster))
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
        UICollectionViewCompositionalLayout { [weak self] index, env in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .featured:
                let width = min(env.container.effectiveContentSize.width * 0.62, 300)
                let size = NSCollectionLayoutSize(widthDimension: .absolute(width), heightDimension: .absolute(width * 1.5 + 92))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
                let s = NSCollectionLayoutSection(group: group)
                s.orthogonalScrollingBehavior = .groupPagingCentered
                s.interGroupSpacing = 4
                s.contentInsets = .init(top: 10, leading: 0, bottom: 40, trailing: 0)
                // Cards on either side fall back and dim, so the one in the middle is the one being presented.
                s.visibleItemsInvalidationHandler = { [weak self] items, offset, env in
                    let mid = offset.x + env.container.contentSize.width / 2
                    var nearest: (Int, CGFloat) = (0, .greatestFiniteMagnitude)
                    for item in items where item.representedElementCategory == .cell {
                        let d = (item.center.x - mid) / item.frame.width
                        let s = 1 - min(abs(d), 1) * 0.14
                        item.transform = CGAffineTransform(scaleX: s, y: s)
                        item.alpha = 1 - min(abs(d), 1) * 0.5
                        if abs(d) < nearest.1 { nearest = (item.indexPath.item, abs(d)) }
                    }
                    let index = nearest.0
                    DispatchQueue.main.async { self?.focus(index) }
                }
                return s
            case .results: return Layouts.posterGrid()
            default: return Layouts.posterRow()
            }
        }
    }

    private func configureDataSource() {
        let featuredReg = UICollectionView.CellRegistration<FeaturedCell, Item> { cell, _, item in cell.configure(item.title) }
        let cellReg = UICollectionView.CellRegistration<PosterCell, Item> { cell, _, item in cell.configure(item.title) }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            if case .reel(let i) = dataSource.sectionIdentifier(for: indexPath.section) {
                header.configure(Reel.discover[i].name, caption: Reel.discover[i].caption)
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            if case .featured = item.section { return cv.dequeueConfiguredReusableCell(using: featuredReg, for: indexPath, item: item) }
            return cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: item)
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
            emptyLabel.setDisplay(searchError ?? "NOTHING ON THE BILL FOR “\((search.searchBar.text ?? "").uppercased())”.")
        } else {
            emptyLabel.isHidden = true
            if !featured.isEmpty {
                snap.appendSections([.featured])
                snap.appendItems(featured.map { Item(section: .featured, title: $0) })
            }
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
            self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) }.map { ($0 as? FeaturedCell)?.card ?? $0 }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        indexPaths.first.flatMap { dataSource.itemIdentifier(for: $0) }.map { titleMenu($0.title) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        glow.transform = CGAffineTransform(translationX: 0, y: -max(y, 0) * 0.5)
    }
}

/// A featured title: a big tilting card with its name set underneath like a poster credit.
final class FeaturedCell: UICollectionViewCell {
    let card = TiltCardView()
    private let name = UILabel.make(Theme.display(28, weight: .black), Theme.text, lines: 2)
    private let meta = UILabel.make(Theme.label(), Theme.secondary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.cornerRadius = 18
        card.maxAngle = 0.16
        [name, meta].forEach { $0.textAlignment = .center }
        let stack = UIStackView(arrangedSubviews: [card, name, meta])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(16, after: card)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            card.heightAnchor.constraint(equalTo: card.widthAnchor, multiplier: 1.5),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: Title) {
        card.setPoster(title.posterPath, size: .posterLarge)
        name.setDisplay(title.name.uppercased())
        name.textAlignment = .center
        let status = Store.shared.tracked(title.id, title.mediaType)?.status
        meta.setCaps([title.mediaType == .movie ? "Film" : "Series", title.year, status.map { "In \($0.label)" }].compactMap { $0 }.joined(separator: " · "))
        accessibilityLabel = [title.name, title.year, status?.label].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool { didSet { Spring.press(card, isHighlighted, scale: 0.96) } }
}
