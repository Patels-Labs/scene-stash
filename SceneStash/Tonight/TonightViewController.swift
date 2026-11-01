import UIKit

final class TonightViewController: UIViewController, UICollectionViewDelegate {
    nonisolated struct UpNext: Hashable { let show: Title; let episode: Episode; let remaining: Int; let runtime: Int? }
    nonisolated struct Upcoming: Hashable { let title: Title; let date: Date; let label: String }
    nonisolated private enum Section: Hashable { case intro, upNext, upcoming, trending }
    nonisolated private enum Item: Hashable { case intro, upNext(UpNext), upcoming(Upcoming), trending(Title) }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var details: [Int: TitleDetail] = [:]
    private var upNext: [UpNext] = []
    private var upcoming: [Upcoming] = []
    private var trending: [Title] = []
    private var refreshTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tonight"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction { [weak self] _ in
            self?.details.removeAll()
            self?.refresh()
        })
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        applySnapshot()
        refresh()
        Task {
            trending = (try? await TMDB.shared.titles(Reel(name: "Trending", path: "trending/all/day"))) ?? []
            applySnapshot()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    @objc private func storeChanged() {
        // Coalesce bursts of saves (e.g. "punch all") into one refresh.
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    // MARK: Data

    private func refresh() {
        Task {
            let tracked = Store.shared.all().filter { $0.status != .seen }
            let shows = tracked.filter { $0.mediaType == .tv }.map(\.title)
            await withTaskGroup(of: TitleDetail?.self) { group in
                for show in shows where details[show.id] == nil {
                    group.addTask { try? await TMDB.shared.detail(show.id, .tv) }
                }
                for await detail in group { if let detail { details[detail.id] = detail } }
            }

            var next: [UpNext] = []
            for tracked in Store.shared.all(.watching) where tracked.mediaType == .tv {
                guard let detail = details[Int(tracked.tmdbID)] else { continue }
                let seasons = Dictionary(uniqueKeysWithValues: detail.mainSeasons.map { ($0.seasonNumber, $0.episodeCount) })
                let aired = detail.lastEpisodeToAir.map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) }
                let watched = Store.shared.watched(show: detail.id)
                guard let key = Progress.nextUp(seasons: seasons, watched: watched, aired: aired),
                      let season = try? await TMDB.shared.season(show: detail.id, number: key.season),
                      let episode = season.episodes.first(where: { $0.episodeNumber == key.episode }) else { continue }
                next.append(UpNext(show: detail.title, episode: episode, remaining: Progress.remaining(seasons: seasons, watched: watched, aired: aired), runtime: episode.runtime ?? detail.runtime))
            }
            upNext = next

            var soon: [Upcoming] = []
            for item in tracked {
                if item.mediaType == .movie, let s = item.releaseDate, let date = DateText.date(s), date > .now {
                    soon.append(Upcoming(title: item.title, date: date, label: "In cinemas"))
                } else if let ep = details[Int(item.tmdbID)]?.nextEpisodeToAir, let s = ep.airDate, let date = DateText.date(s) {
                    soon.append(Upcoming(title: item.title, date: date, label: ep.episodeNumber == 1 ? "Season \(ep.seasonNumber) premiere" : "S\(ep.seasonNumber) · E\(ep.episodeNumber)"))
                }
            }
            upcoming = soon.sorted { $0.date < $1.date }
            collectionView.refreshControl?.endRefreshing()
            applySnapshot()
        }
    }

    private func punch(_ item: UpNext) {
        Haptics.thunk()
        Store.shared.setWatched([EpisodeKey(season: item.episode.seasonNumber, episode: item.episode.episodeNumber)], watched: true, show: item.show, runtime: item.runtime)
    }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, env in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .intro:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
                s.contentInsets = .init(top: 4, leading: 20, bottom: 24, trailing: 20)
                return s
            case .upNext:
                let width = min(env.container.effectiveContentSize.width - 56, 380)
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(width), heightDimension: .absolute(width * 0.5625 + 92)), subitems: [item])
                let s = NSCollectionLayoutSection(group: group)
                s.orthogonalScrollingBehavior = .groupPagingCentered
                s.interGroupSpacing = 14
                s.contentInsets = .init(top: 10, leading: 20, bottom: 30, trailing: 20)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                // Cards tilt slightly as they slide, like stubs fanned in a hand.
                s.visibleItemsInvalidationHandler = { items, offset, env in
                    guard !UIAccessibility.isReduceMotionEnabled else { return }
                    let mid = offset.x + env.container.contentSize.width / 2
                    for item in items where item.representedElementCategory == .cell {
                        let d = (item.center.x - mid) / env.container.contentSize.width
                        item.transform = CGAffineTransform(rotationAngle: d * 0.08).scaledBy(x: 1 - abs(d) * 0.08, y: 1 - abs(d) * 0.08)
                    }
                }
                return s
            case .upcoming:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(64))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
                s.interGroupSpacing = 10
                s.contentInsets = .init(top: 10, leading: 20, bottom: 30, trailing: 20)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            default:
                return Layouts.posterRow()
            }
        }
    }

    private func configureDataSource() {
        let introReg = UICollectionView.CellRegistration<IntroCell, Item> { [unowned self] cell, _, _ in
            cell.configure(watching: upNext.count, empty: Store.shared.all().isEmpty)
            cell.onDiscover = { [weak self] in guard let tabs = self?.tabBarController else { return }; tabs.selectedTab = tabs.tabs.first { $0 is UISearchTab } }
        }
        let upNextReg = UICollectionView.CellRegistration<UpNextCell, Item> { [unowned self] cell, _, item in
            guard case .upNext(let u) = item else { return }
            cell.configure(u)
            cell.onPunch = { [weak self] in self?.punch(u) }
        }
        let upcomingReg = UICollectionView.CellRegistration<UpcomingCell, Item> { cell, _, item in
            if case .upcoming(let u) = item { cell.configure(u) }
        }
        let posterReg = UICollectionView.CellRegistration<PosterCell, Item> { cell, _, item in
            if case .trending(let t) = item { cell.configure(t) }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .upNext: header.configure("Up next", caption: "Pick up where you left off")
            case .upcoming: header.configure("Coming soon", caption: "From your stash")
            case .trending: header.configure("Everyone's watching", caption: "Trending today")
            default: header.configure("")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .intro: cv.dequeueConfiguredReusableCell(using: introReg, for: indexPath, item: item)
            case .upNext: cv.dequeueConfiguredReusableCell(using: upNextReg, for: indexPath, item: item)
            case .upcoming: cv.dequeueConfiguredReusableCell(using: upcomingReg, for: indexPath, item: item)
            case .trending: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.intro]); snap.appendItems([.intro])
        if !upNext.isEmpty { snap.appendSections([.upNext]); snap.appendItems(upNext.map(Item.upNext)) }
        if !upcoming.isEmpty { snap.appendSections([.upcoming]); snap.appendItems(upcoming.prefix(8).map(Item.upcoming)) }
        if !trending.isEmpty { snap.appendSections([.trending]); snap.appendItems(trending.map(Item.trending)) }
        snap.reconfigureItems([.intro])
        dataSource.apply(snap, animatingDifferences: !UIAccessibility.isReduceMotionEnabled)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .intro
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        let title: Title
        switch item {
        case .upNext(let u): title = u.show
        case .upcoming(let u): title = u.title
        case .trending(let t): title = t
        case .intro: return
        }
        Haptics.tap()
        openDetail(title) { [weak self] in
            self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .trending(let t) = dataSource.itemIdentifier(for: ip) else { return nil }
        return titleMenu(t)
    }
}

// MARK: - Cells

final class IntroCell: UICollectionViewCell {
    var onDiscover: (() -> Void)?
    private let date = UILabel()
    private let line = UILabel()
    private let button = UIButton(configuration: .prominentGlass())

    override init(frame: CGRect) {
        super.init(frame: frame)
        date.font = Theme.mono(.caption1, weight: .bold)
        date.textColor = Theme.amber
        line.font = Theme.serif(.title2, weight: .regular)
        line.textColor = Theme.paper
        line.numberOfLines = 0
        [date, line].forEach { $0.adjustsFontForContentSizeCategory = true }
        button.configuration?.title = "Find something to watch"
        button.configuration?.image = UIImage(systemName: "sparkle.magnifyingglass")
        button.configuration?.imagePadding = 8
        button.tintColor = Theme.amber
        button.addAction(UIAction { [weak self] _ in self?.onDiscover?() }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [date, line, button])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(18, after: line)
        contentView.addSubview(stack)
        stack.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(watching: Int, empty: Bool) {
        let now = Date.now
        date.text = now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
        let hour = Calendar.current.component(.hour, from: now)
        let greeting = hour < 5 ? "Late show." : hour < 12 ? "Morning matinee." : hour < 18 ? "Afternoon screening." : "Lights down."
        if empty {
            line.text = "\(greeting) Your stash is empty — let's find your first ticket."
        } else if watching > 0 {
            line.text = "\(greeting) \(watching) show\(watching == 1 ? " is" : "s are") waiting for you."
        } else {
            line.text = "\(greeting) You're all caught up."
        }
        button.isHidden = !empty
    }
}

final class UpNextCell: UICollectionViewCell {
    var onPunch: (() -> Void)?
    private let still = UIImageView()
    private let show = UILabel()
    private let episode = UILabel()
    private let left = UILabel()
    private let punch = PunchButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Theme.inkRaised
        contentView.layer.cornerRadius = 18
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        still.contentMode = .scaleAspectFill
        still.clipsToBounds = true
        show.font = Theme.serif(.title3)
        show.textColor = Theme.paper
        episode.font = Theme.mono(.caption1, weight: .medium)
        episode.textColor = Theme.muted
        episode.numberOfLines = 1
        left.font = Theme.mono(.caption2, weight: .bold)
        left.textColor = Theme.amber
        [show, episode, left].forEach { $0.adjustsFontForContentSizeCategory = true }
        punch.addAction(UIAction { [weak self] _ in
            // Let the punch land before the card flips to the next episode.
            self?.punch.set(true, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.onPunch?() }
        }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [left, show, episode])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [text, punch])
        row.alignment = .center
        row.spacing = 8
        let stack = UIStackView(arrangedSubviews: [still, row])
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 0, leading: 0, bottom: 14, trailing: 0)
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 0, leading: 16, bottom: 0, trailing: 10)
        contentView.addSubview(stack)
        stack.pin(to: contentView)
        still.heightAnchor.constraint(equalTo: still.widthAnchor, multiplier: 0.5625).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: TonightViewController.UpNext) {
        still.setImage(TMDB.imageURL(item.episode.stillPath, .backdrop) ?? TMDB.imageURL(item.show.backdropPath, .backdrop))
        show.text = item.show.name
        episode.text = "S\(item.episode.seasonNumber) · E\(item.episode.episodeNumber)  \(item.episode.name)"
        left.text = item.remaining > 1 ? "\(item.remaining) EPISODES TO GO" : "FINAL AIRED EPISODE"
        punch.set(false, animated: false)
        punch.accessibilityLabel = "Mark \(item.show.name) season \(item.episode.seasonNumber) episode \(item.episode.episodeNumber) watched"
        isAccessibilityElement = false
    }
}

final class UpcomingCell: UICollectionViewCell {
    private let day = UILabel()
    private let month = UILabel()
    private let name = UILabel()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        day.font = Theme.serif(.title2, weight: .heavy)
        day.textColor = Theme.ink
        month.font = Theme.mono(.caption2, weight: .bold)
        month.textColor = Theme.ink
        let dateStack = UIStackView(arrangedSubviews: [month, day])
        dateStack.axis = .vertical
        dateStack.alignment = .center
        dateStack.spacing = -2
        let chip = UIView()
        chip.backgroundColor = Theme.amber
        chip.layer.cornerRadius = 10
        chip.layer.cornerCurve = .continuous
        chip.addSubview(dateStack)
        dateStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 56), chip.heightAnchor.constraint(equalToConstant: 56),
            dateStack.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            dateStack.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
        ])
        name.font = Theme.serif(.headline)
        name.textColor = Theme.paper
        label.font = Theme.mono(.caption1, weight: .medium)
        label.textColor = Theme.muted
        [name, label].forEach { $0.adjustsFontForContentSizeCategory = true; $0.numberOfLines = 2 }
        let text = UIStackView(arrangedSubviews: [name, label])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [chip, text])
        row.alignment = .center
        row.spacing = 14
        contentView.addSubview(row)
        row.pin(to: contentView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: TonightViewController.Upcoming) {
        day.text = item.date.formatted(.dateTime.day())
        month.text = item.date.formatted(.dateTime.month(.abbreviated)).uppercased()
        name.text = item.title.name
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: item.date).day ?? 0
        let when = days <= 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
        label.text = "\(item.label.uppercased()) · \(when.uppercased())"
        accessibilityLabel = "\(item.title.name), \(item.label), \(item.date.formatted(date: .long, time: .omitted))"
    }
}
