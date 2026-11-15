import UIKit

/// A film series in watch order: the series' art with Next and a marathon of the rest, how far through you
/// are, and each film with a tick.
final class CollectionViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Item: Hashable { case hero, film(Title) }

    private let id: Int
    private let name: String
    private var parts: [Title] = []
    private var runtimes: [Int: Int] = [:]
    private let hero = HeroView()
    private let primary = CapsuleButton.primary("Next", image: "play.fill")
    private let marathon = CapsuleButton.glass("Plan the Rest as a Marathon", image: "calendar")
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!

    init(id: Int, name: String, poster: String?, backdrop: String?) {
        self.id = id
        self.name = name.replacingOccurrences(of: " Collection", with: "")
        super.init(nibName: nil, bundle: nil)
        hero.show(Title(id: id, mediaType: .collection, name: self.name, posterPath: poster, backdropPath: backdrop), meta: "Collection")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = 100
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        [primary, marathon].forEach {
            hero.content.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: hero.content.widthAnchor).isActive = true
        }
        hero.content.setCustomSpacing(10, after: primary)
        primary.addAction(UIAction { [weak self] _ in self?.startNext() }, for: .primaryActionTriggered)
        marathon.addAction(UIAction { [weak self] _ in self?.withPass { self?.planMarathon() } }, for: .primaryActionTriggered)

        let heroReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(hero) }
        let filmReg = UICollectionView.CellRegistration<OrderCell, Item> { [unowned self] cell, _, item in
            guard case .film(let t) = item else { return }
            let seen = seen(t)
            cell.configure(t, number: (parts.firstIndex(of: t) ?? 0) + 1, next: t == nextUp, seen: seen, runtime: runtimes[t.id])
            cell.onTick = { [weak self] in
                Haptics.success()
                Store.shared.track(t, status: seen ? .watchlist : .seen, runtime: self?.runtimes[t.id])
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SeasonHeader>(elementKind: SeasonHeader.kind) { [unowned self] header, _, _ in
            configureHeader(header)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, item in
            item == .hero ? cv.dequeueConfiguredReusableCell(using: heroReg, for: ip, item: item) : cv.dequeueConfiguredReusableCell(using: filmReg, for: ip, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: ip) }
        render()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    private func load() {
        Task {
            do {
                parts = try await TMDB.shared.series(id).parts
                render()
                await withTaskGroup(of: (Int, Int?).self) { group in
                    for part in parts { group.addTask { (part.id, await TMDB.shared.runtime(part.id)) } }
                    for await (id, runtime) in group { runtimes[id] = runtime }
                }
                render()
            } catch {
                showError(error)
            }
        }
    }

    @objc private func storeChanged() { render() }

    private func seen(_ t: Title) -> Bool { Store.shared.tracked(t.id, .movie)?.status == .seen }
    private var nextUp: Title? { parts.first { !seen($0) } }

    private func render() {
        let left = parts.filter { !seen($0) }
        let toGo = left.reduce(0) { $0 + (runtimes[$1.id] ?? 0) }
        var meta = ["Collection"]
        if !parts.isEmpty { meta += ["\(parts.count) films", "\(parts.count - left.count) seen"] }
        if toGo > 0 { meta.append("\(DateText.runtime(toGo)) to go") }
        hero.meta.text = meta.joined(separator: " · ")
        if let next = nextUp {
            let resume = (Store.shared.tracked(next.id, .movie)?.position ?? 0) > 0
            primary.configuration?.title = (resume ? "Resume: " : "Next: ") + next.name
            primary.configuration?.image = UIImage(systemName: "play.fill")
        } else {
            primary.configuration?.title = parts.isEmpty ? "Loading…" : "All Watched"
            primary.configuration?.image = parts.isEmpty ? nil : UIImage(systemName: "checkmark")
        }
        primary.isEnabled = nextUp != nil
        marathon.isHidden = left.count < 2

        var snap = NSDiffableDataSourceSnapshot<Int, Item>()
        snap.appendSections([0, 1])
        snap.appendItems([.hero], toSection: 0)
        snap.appendItems(parts.map(Item.film), toSection: 1)
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
        collectionView.visibleSupplementaryViews(ofKind: SeasonHeader.kind).compactMap { $0 as? SeasonHeader }.forEach(configureHeader)
    }

    private func configureHeader(_ header: SeasonHeader) {
        let next = nextUp
        header.configure(title: "Release Order", menu: nil, states: parts.map { seen($0) ? 2 : $0 == next ? 1 : 0 })
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { index, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(index == 0 ? 860 : 72))
            let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
            guard index == 1 else { s.contentInsets.bottom = 26; return s }
            s.interGroupSpacing = 14
            s.contentInsets = .init(top: 0, leading: Shelf.margin, bottom: 0, trailing: Shelf.margin)
            s.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(50)),
                                                                                        elementKind: SeasonHeader.kind, alignment: .top)]
            return s
        }
    }

    // MARK: Actions

    /// Starts the next film on the clock, or picks up where you left it.
    private func startNext() {
        guard let next = nextUp else { return }
        Haptics.tap()
        Task {
            guard let detail = try? await TMDB.shared.detail(next.id, .movie), let runtime = detail.runtime, runtime > 0 else {
                openDetail(next) { nil }
                return
            }
            let tracked = Store.shared.tracked(next.id, .movie)
            let from = tracked?.status == .seen ? 0 : Int(tracked?.position ?? 0)
            withPass { Task { await WatchSession.shared.start(detail.title, runtime: runtime, from: from, stinger: detail.midCredits || detail.afterCredits) } }
        }
    }

    private func planMarathon() {
        Haptics.tap()
        // ponytail: unwatched parts only; rewatch marathons would need per-marathon progress.
        let pieces = parts.filter { !seen($0) }.map {
            Piece(id: $0.id, isEpisode: false, name: $0.name, detail: nil, poster: $0.posterPath, backdrop: $0.backdropPath, minutes: runtimes[$0.id] ?? 120)
        }
        guard !pieces.isEmpty else { return }
        navigationController?.pushViewController(MarathonPlannerViewController(name: name, pieces: pieces), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { indexPath.section == 1 }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .film(let t) = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        openDetail(t) { [weak self] in self?.dataSource.indexPath(for: .film(t)).flatMap { collectionView.cellForItem(at: $0) } }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationItem.title = scrollView.contentOffset.y > 520 ? name : nil
    }
}

/// A film in a series: its backdrop, which part it is, its name, and a tick.
final class OrderCell: UICollectionViewCell {
    var onTick: (() -> Void)?
    private let art = ArtView(radius: 10)
    private let part = UILabel.make(Theme.text(.caption1, weight: .semibold), Theme.secondary)
    private let name = UILabel.make(Theme.text(.body, weight: .semibold), Theme.text, lines: 2)
    private let meta = UILabel.make(Theme.text(.footnote), Theme.secondary)
    private let tick = UIButton(type: .system)
    private static let tickSize = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let text = UIStackView(arrangedSubviews: [part, name, meta])
        text.axis = .vertical
        text.spacing = 1
        let row = UIStackView(arrangedSubviews: [art, text, tick])
        row.spacing = 12
        row.alignment = .center
        contentView.addSubview(row)
        row.pin(to: contentView)
        tick.addAction(UIAction { [weak self] _ in self?.onTick?() }, for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            art.widthAnchor.constraint(equalToConstant: 128),
            art.heightAnchor.constraint(equalToConstant: 72),
            tick.widthAnchor.constraint(equalToConstant: 44),
            tick.heightAnchor.constraint(equalToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ t: Title, number: Int, next: Bool, seen: Bool, runtime: Int?) {
        art.show(TMDB.imageURL(t.backdropPath, .still), name: t.name)
        part.text = next ? "Up Next · Part \(number)" : "Part \(number)"
        part.textColor = next ? Theme.accent : Theme.secondary
        name.text = t.name
        meta.text = [t.year, runtime.map(DateText.runtime)].compactMap { $0 }.joined(separator: " · ")
        let image = seen
            ? UIImage(systemName: "checkmark.circle.fill", withConfiguration: Self.tickSize.applying(UIImage.SymbolConfiguration(paletteColors: [.black, Theme.accent])))
            : UIImage(systemName: "circle", withConfiguration: Self.tickSize)
        tick.setImage(image, for: .normal)
        tick.tintColor = seen ? nil : Theme.secondary
        contentView.alpha = seen ? 0.6 : 1
        accessibilityLabel = [part.text, t.name, meta.text, seen ? "watched" : nil].compactMap { $0 }.joined(separator: ", ")
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: seen ? "Mark as Not Watched" : "Mark as Watched") { [weak self] _ in self?.onTick?(); return true }]
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.98) } }
}
