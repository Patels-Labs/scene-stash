import UIKit

final class TonightViewController: UIViewController, UICollectionViewDelegate {
    nonisolated struct UpNext: Hashable { let show: Title; let episode: Episode; let remaining: Int; let runtime: Int? }
    nonisolated struct Upcoming: Hashable { let title: Title; let date: Date; let label: String }
    nonisolated private enum Section: Hashable { case intro, upNext, watchlist, upcoming, trending }
    nonisolated private enum Item: Hashable { case intro, upNext(UpNext), watchlist(Title), upcoming(Upcoming), trending(Title) }

    private let glow = GlowView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var details: [Int: TitleDetail] = [:]
    private var upNext: [UpNext] = []
    private var upcoming: [Upcoming] = []
    private var trending: [Title] = []
    private var refreshTask: Task<Void, Never>?
    private var focusedShow = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tonight"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        view.addSubview(glow)
        glow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: view.topAnchor),
            glow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glow.heightAnchor.constraint(equalToConstant: 640),
        ])
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
            if upNext.isEmpty { glow.show(TMDB.imageURL(trending.first?.posterPath, .poster)) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    @objc private func storeChanged() {
        // Coalesce bursts of saves (e.g. "mark all") into one refresh.
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
            focus(min(max(focusedShow, 0), max(upNext.count - 1, 0)), force: true)
        }
    }

    private func markWatched(_ item: UpNext) {
        Store.shared.setWatched([EpisodeKey(season: item.episode.seasonNumber, episode: item.episode.episodeNumber)], watched: true, show: item.show, runtime: item.runtime)
    }

    /// The room takes on the colours of whichever show is in front of you.
    private func focus(_ index: Int, force: Bool = false) {
        guard force || index != focusedShow, let item = upNext[safe: index] else { return }
        focusedShow = index
        glow.show(TMDB.imageURL(item.show.posterPath, .poster))
    }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, env in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .intro:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
                s.contentInsets = .init(top: 0, leading: 20, bottom: 18, trailing: 20)
                return s
            case .upNext:
                let width = env.container.effectiveContentSize.width - 40
                let size = NSCollectionLayoutSize(widthDimension: .absolute(width), heightDimension: .estimated(width * 0.5625 + 230))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
                let s = NSCollectionLayoutSection(group: group)
                s.orthogonalScrollingBehavior = .groupPagingCentered
                s.interGroupSpacing = 16
                s.contentInsets = .init(top: 4, leading: 20, bottom: 40, trailing: 20)
                s.visibleItemsInvalidationHandler = { [weak self] items, offset, env in
                    let mid = offset.x + env.container.contentSize.width / 2
                    guard let nearest = items.filter({ $0.representedElementCategory == .cell })
                        .min(by: { abs($0.center.x - mid) < abs($1.center.x - mid) }) else { return }
                    let index = nearest.indexPath.item
                    DispatchQueue.main.async { self?.focus(index) }
                }
                return s
            case .upcoming:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(76))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
                s.interGroupSpacing = 0
                s.contentInsets = .init(top: 8, leading: 20, bottom: 40, trailing: 20)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            default:
                return Layouts.posterRow()
            }
        }
    }

    private func configureDataSource() {
        let introReg = UICollectionView.CellRegistration<IntroCell, Item> { [unowned self] cell, _, _ in
            cell.configure(waiting: upNext.count, empty: Store.shared.all().isEmpty)
            cell.onDiscover = { [weak self] in
                guard let tabs = self?.tabBarController else { return }
                tabs.selectedTab = tabs.tabs.first { $0 is UISearchTab }
            }
        }
        let upNextReg = UICollectionView.CellRegistration<UpNextCell, Item> { [unowned self] cell, _, item in
            guard case .upNext(let u) = item else { return }
            cell.configure(u)
            cell.onWatched = { [weak self] in self?.markWatched(u) }
        }
        let upcomingReg = UICollectionView.CellRegistration<UpcomingCell, Item> { cell, _, item in
            if case .upcoming(let u) = item { cell.configure(u) }
        }
        let posterReg = UICollectionView.CellRegistration<PosterCell, Item> { cell, _, item in
            if case .trending(let t) = item { cell.configure(t) }
            if case .watchlist(let t) = item { cell.configure(t) }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .watchlist: header.configure("Your watchlist", caption: "Already out")
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
            case .trending, .watchlist: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
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
        let ready = Store.shared.all(.watchlist).map(\.title).filter { $0.date.map { DateText.isPast($0) } ?? true }
        if !ready.isEmpty { snap.appendSections([.watchlist]); snap.appendItems(ready.map(Item.watchlist)) }
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
        case .trending(let t), .watchlist(let t): title = t
        case .intro: return
        }
        Haptics.tap()
        openDetail(title) { [weak self] in
            self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        switch indexPaths.first.flatMap({ dataSource.itemIdentifier(for: $0) }) {
        case .trending(let t), .watchlist(let t): return titleMenu(t)
        default: return nil
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        glow.transform = CGAffineTransform(translationX: 0, y: -max(y, 0) * 0.5)
    }
}

// MARK: - Cells

final class IntroCell: UICollectionViewCell {
    var onDiscover: (() -> Void)?
    private let date = UILabel.make(Theme.label(), Theme.secondary)
    private let empty = UILabel.make(Theme.display(40, weight: .black), Theme.text, lines: 0)
    private let body = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)
    private let button = PillButton("Find something to watch", image: "sparkle.magnifyingglass")

    override init(frame: CGRect) {
        super.init(frame: frame)
        empty.setDisplay("NOTHING ON\nTONIGHT, YET.")
        body.text = "Stash a film or start a show, and this is where tonight's picks will be waiting."
        button.addAction(UIAction { [weak self] _ in self?.onDiscover?() }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [date, empty, body, button])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(26, after: date)
        stack.setCustomSpacing(22, after: body)
        contentView.addSubview(stack)
        stack.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(waiting: Int, empty isEmpty: Bool) {
        var line = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if waiting > 0 { line += " · \(waiting) show\(waiting == 1 ? "" : "s") waiting" }
        date.setCaps(line)
        [empty, body, button].forEach { $0.isHidden = !isEmpty }
    }
}

/// The next episode of a show as a big card: still, title like a poster, one button.
final class UpNextCell: UICollectionViewCell {
    var onWatched: (() -> Void)?
    private let still = TiltCardView()
    private let code = UILabel.make(Theme.label(.caption1, weight: .bold), Theme.accent)
    private let show = UILabel.make(Theme.display(40, weight: .black), Theme.text, lines: 2)
    private let episode = UILabel.make(Theme.text(.callout), Theme.secondary, lines: 1)
    private let ticket = TicketButton()
    private var shownID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        still.maxAngle = 0.08
        still.cornerRadius = 18
        // Tear the stub off to mark it watched; the stub flies up and out of frame.
        ticket.onStash = { [weak self] in
            guard let self, let window else { return }
            let target = CGPoint(x: window.bounds.maxX - 40, y: -60)
            ticket.tear(to: target) { [weak self] in self?.onWatched?() }
        }
        let text = UIStackView(arrangedSubviews: [code, show, episode])
        text.axis = .vertical
        text.spacing = 4
        let stack = UIStackView(arrangedSubviews: [still, text, ticket])
        stack.axis = .vertical
        stack.spacing = 18
        stack.setCustomSpacing(20, after: text)
        contentView.addSubview(stack)
        stack.pin(to: contentView)
        still.heightAnchor.constraint(equalTo: still.widthAnchor, multiplier: 0.5625).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: TonightViewController.UpNext) {
        still.imageView.setImage(TMDB.imageURL(item.episode.stillPath, .backdrop) ?? TMDB.imageURL(item.show.backdropPath, .backdrop))
        var bits = ["S\(item.episode.seasonNumber) · E\(item.episode.episodeNumber)"]
        if let runtime = item.runtime { bits.append("\(runtime) min") }
        bits.append(item.remaining > 1 ? "\(item.remaining) to go" : "Latest episode")
        code.setCaps(bits.joined(separator: "  ·  "), kern: 1.2)
        show.setDisplay(item.show.name.uppercased())
        episode.text = item.episode.name
        ticket.setTint(Theme.accent)
        code.textColor = Theme.accent
        let id = item.show.id
        shownID = id
        if let url = TMDB.imageURL(item.show.posterPath, .poster) {
            Task { [weak self] in
                guard let tint = await ImageLoader.shared.tint(for: url), let self, shownID == id else { return }
                ticket.setTint(tint)
                code.textColor = tint
            }
        }
        ticket.configure(label: "Mark watched", symbol: "checkmark",
                         accessibility: "Mark \(item.show.name) season \(item.episode.seasonNumber) episode \(item.episode.episodeNumber) watched")
    }
}

/// A schedule row: the date set large, like a departures board.
final class UpcomingCell: UICollectionViewCell {
    private let day = UILabel.make(Theme.display(38, weight: .black))
    private let month = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.accent)
    private let name = UILabel.make(Theme.text(.headline, weight: .semibold), Theme.text, lines: 2)
    private let label = UILabel.make(Theme.label(), Theme.secondary, lines: 1)
    private let poster = UIImageView()
    private let rule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        day.textAlignment = .center
        month.textAlignment = .center
        let date = UIStackView(arrangedSubviews: [month, day])
        date.axis = .vertical
        date.spacing = -4
        date.widthAnchor.constraint(equalToConstant: 52).isActive = true
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 6
        poster.backgroundColor = Theme.surface
        let text = UIStackView(arrangedSubviews: [name, label])
        text.axis = .vertical
        text.spacing = 3
        let row = UIStackView(arrangedSubviews: [date, text, poster])
        row.alignment = .center
        row.spacing = 16
        rule.backgroundColor = Theme.hairline
        [row, rule].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            poster.widthAnchor.constraint(equalToConstant: 40), poster.heightAnchor.constraint(equalToConstant: 60),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            rule.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: TonightViewController.Upcoming) {
        day.text = item.date.formatted(.dateTime.day())
        month.setCaps(item.date.formatted(.dateTime.month(.abbreviated)), kern: 1)
        name.text = item.title.name
        poster.setImage(TMDB.imageURL(item.title.posterPath, .poster))
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: item.date).day ?? 0
        let when = days <= 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
        label.setCaps("\(item.label) · \(when)", kern: 1)
        accessibilityLabel = "\(item.title.name), \(item.label), \(item.date.formatted(date: .long, time: .omitted))"
    }
}
