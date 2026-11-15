import UIKit
import WidgetKit

/// Tonight's programme: what you're in the middle of, laid out on the clock from now until lights up.
final class TonightViewController: UIViewController, UICollectionViewDelegate {
    nonisolated struct UpNext: Hashable { let show: Title; let episode: Episode; let remaining: Int; let runtime: Int?; var position = 0 }
    nonisolated struct Film: Hashable { let title: Title; let position: Int; let runtime: Int }
    nonisolated struct Upcoming: Hashable { let title: Title; let date: Date; let label: String }
    /// Tonight's night out: blocked from doors until the lights come up.
    nonisolated struct Outing: Hashable { let uuid: String; let title: Title; let place: String?; let minutes: Int }
    nonisolated enum Slot: Hashable {
        case episode(UpNext), film(Film), pick(Film), free, intermission(Int)
        /// A night out, and the time before it to get there.
        case outing(Outing), headOut(Int)

        var minutes: Int {
            switch self {
            case .episode(let u): max((u.runtime ?? 45) - u.position / 60, 1)
            case .film(let f): max(f.runtime - f.position / 60, 1)
            case .pick(let f): f.runtime
            case .free: 0
            case .intermission(let m), .headOut(let m): m
            case .outing(let o): o.minutes
            }
        }
        var title: Title? {
            switch self {
            case .episode(let u): u.show
            case .film(let f), .pick(let f): f.title
            case .outing(let o): o.title
            case .free, .intermission, .headOut: nil
            }
        }
    }
    nonisolated private enum Section: Hashable { case hero, night, watchlist, upcoming, trending }
    nonisolated private enum Item: Hashable { case hero, night(String), watchlist(Title), upcoming(Upcoming), trending(Title) }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var details: [Int: TitleDetail] = [:]
    private var upNext: [UpNext] = []
    private var programme: [Slot] = []
    /// False until the first programme is worked out, so the hero doesn't offer "nothing on" while it loads.
    private var planned = false
    private var upcoming: [Upcoming] = []
    private var trending: [Title] = []
    private var refreshTask: Task<Void, Never>?
    private var clock: Timer?
    /// Today's marathon, when there is one: its name and when its doors open.
    private var marathon: (name: String, doors: Date)?
    /// Tonight's night out, when there is one: the programme bends around its showtime.
    private var outingTimes: (showtime: Date, lightsUp: Date)?
    private var doors: Date { marathon?.doors ?? min(Self.doors(), outingTimes?.showtime ?? .distantFuture) }
    /// Midnight-ish, or later if tonight's film runs past it.
    private var lightsUp: Date { max(Self.lightsUp(), outingTimes?.lightsUp ?? .distantPast) }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(true, animated: false)
        collectionView.backgroundColor = .clear
        // The hero's art runs up under the status bar, like the TV app.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = 100
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // The clock on the page is live: start times and the countdown move with the minute.
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        heroCell?.onScreen = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        clock?.invalidate()
        heroCell?.onScreen = false
    }

    private var heroCell: TonightHeroCell? { collectionView.visibleCells.lazy.compactMap { $0 as? TonightHeroCell }.first }

    private func tick() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems([.hero])
        dataSource.apply(snap, animatingDifferences: false)
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
        Store.shared.updateFromNights()
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
                next.append(UpNext(show: detail.title, episode: episode, remaining: Progress.remaining(seasons: seasons, watched: watched, aired: aired), runtime: episode.runtime ?? detail.runtime, position: Int(tracked.position)))
            }
            upNext = next
            programme = buildProgramme()
            planned = true
            Alerts.reschedule(Array(details.values))

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
            await writeWidgets()
        }
    }

    /// The next episode of your first show leads, then any film you're partway through, then the rest.
    /// If there's room before lights up, a released film from the watchlist fills it.
    private func buildProgramme() -> [Slot] {
        // A marathon day takes over the programme: its pieces in order, intermissions between.
        if let (m, _, planned) = Store.shared.marathonToday(), let first = planned.first {
            marathon = (m.name ?? "Marathon", first.start)
            var slots: [Slot] = []
            for (i, p) in planned.enumerated() {
                if p.piece.isEpisode, let s = p.piece.season, let e = p.piece.episode {
                    let show = Title(id: p.piece.id, mediaType: .tv, name: p.piece.name, posterPath: p.piece.poster, backdropPath: p.piece.backdrop)
                    let episode = Episode(id: p.piece.id * 10_000 + s * 100 + e, seasonNumber: s, episodeNumber: e, name: p.piece.detail ?? "Episode \(e)",
                                          overview: nil, stillPath: nil, airDate: nil, runtime: p.piece.minutes)
                    slots.append(.episode(UpNext(show: show, episode: episode, remaining: 0, runtime: p.piece.minutes)))
                } else {
                    let film = Title(id: p.piece.id, mediaType: .movie, name: p.piece.name, posterPath: p.piece.poster, backdropPath: p.piece.backdrop)
                    let position = Int(Store.shared.tracked(p.piece.id, .movie)?.position ?? 0)
                    slots.append(.film(Film(title: film, position: position, runtime: p.piece.minutes)))
                }
                if i < planned.count - 1 {
                    let gap = Int(planned[i + 1].start.timeIntervalSince(p.end) / 60)
                    if gap > 0 { slots.append(.intermission(gap)) }
                }
            }
            return slots
        }
        marathon = nil
        let night = Store.shared.tonightsNight()
        outingTimes = night.flatMap { n in n.showtime.flatMap { s in n.lightsUp.map { (s, $0) } } }
        let films = Store.shared.all(.watching).filter { $0.mediaType == .movie && $0.runtime > 0 && Int($0.tmdbID) != night.map { Int($0.tmdbID) } }
            .map { Slot.film(Film(title: $0.title, position: Int($0.position), runtime: Int($0.runtime))) }
        var slots = Array(upNext.prefix(1).map(Slot.episode)) + films + upNext.dropFirst().map(Slot.episode)
        if let night, let uuid = night.uuid, let times = outingTimes {
            return Self.around(night: Outing(uuid: uuid, title: night.title, place: night.whereLine, minutes: 0),
                               showtime: times.showtime, lightsUp: times.lightsUp, doors: doors, queue: slots)
        }
        let used = slots.reduce(0) { $0 + $1.minutes }
        let left = Int(lightsUp.timeIntervalSince(doors) / 60) - used
        if let pick = Store.shared.all(.watchlist).first(where: {
            $0.mediaType == .movie && $0.runtime > 0 && Int($0.runtime) <= left && ($0.releaseDate.map { DateText.isPast($0) } ?? true)
        }) {
            slots.append(.pick(Film(title: pick.title, position: 0, runtime: Int(pick.runtime))))
        }
        let rest = left - slots.reduce(0) { $0 + $1.minutes } + used
        if !slots.isEmpty, rest >= 20 { slots.append(.free) }
        return slots
    }

    /// A night out holds its place: what fits before it plays first (leaving half an hour to get there),
    /// then the gap to head out, the night itself, and the rest of the programme after.
    nonisolated static func around(night: Outing, showtime: Date, lightsUp: Date, doors: Date, queue: [Slot]) -> [Slot] {
        var queue = queue, slots: [Slot] = [], t = doors
        let leave = showtime - 30 * 60
        while let next = queue.first, t + TimeInterval(next.minutes * 60) <= leave {
            slots.append(next)
            t += TimeInterval(next.minutes * 60)
            queue.removeFirst()
        }
        let gap = Int(showtime.timeIntervalSince(t) / 60)
        if gap > 0 { slots.append(.headOut(gap)) }
        let start = max(showtime, doors)
        slots.append(.outing(Outing(uuid: night.uuid, title: night.title, place: night.place, minutes: max(Int(lightsUp.timeIntervalSince(start) / 60), 1))))
        return slots + queue
    }

    /// Midnight, unless that's under an hour away (or past), in which case two hours from now.
    static func lightsUp(now: Date = .now) -> Date {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let hour = cal.component(.hour, from: now)
        return hour >= 5 && midnight.timeIntervalSince(now) >= 3600 ? midnight : now.addingTimeInterval(2 * 3600)
    }

    /// Hands the Home Screen widgets what they show: the programme, the next premiere, and a punch card.
    private func writeWidgets() async {
        var snap = WidgetSnapshot()
        snap.unlocked = Pass.shared.isUnlocked
        snap.doors = doors
        snap.booked = programme.reduce(0) { $0 + $1.minutes }
        let times = startTimes()
        for (slot, start) in zip(programme, times).prefix(4) {
            guard let title = slot.title else { continue }
            var tint = "F5B544"
            if let url = TMDB.imageURL(title.posterPath, .poster), let color = await ImageLoader.shared.tint(for: url) { tint = color.hex }
            await saveWidgetArt(title)
            let code: String
            switch slot {
            case .episode(let u): code = "S\(u.episode.seasonNumber) E\(u.episode.episodeNumber)"
            case .film(let f): code = "\(max(f.runtime - f.position / 60, 0))m left"
            case .outing(let o): code = o.place ?? "Night out"
            default: code = DateText.runtime(slot.minutes)
            }
            snap.programme.append(.init(id: title.id, type: title.mediaType.rawValue, name: title.name, code: code, start: start, tint: tint))
        }
        if let next = upcoming.first(where: { $0.label.contains("premiere") || $0.label == "In cinemas" }) ?? upcoming.first {
            snap.premiere = .init(id: next.title.id, type: next.title.mediaType.rawValue, name: next.title.name, label: next.label, date: next.date)
            await saveWidgetArt(next.title)
        }
        if let u = upNext.first, let detail = details[u.show.id] {
            let season = u.episode.seasonNumber
            let count = detail.mainSeasons.first { $0.seasonNumber == season }?.episodeCount ?? 0
            let watched = Store.shared.watched(show: detail.id)
            let holes = (1...max(count, 1)).map { e in
                watched.contains(EpisodeKey(season: season, episode: e)) ? 1 : e == u.episode.episodeNumber ? 2 : 0
            }
            snap.card = .init(id: detail.id, name: detail.name, season: season, holes: count == 0 ? [] : holes, left: u.remaining)
            await saveWidgetArt(u.show)
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Widgets fill with the poster, and can't download one themselves. A running title's copy stays as its Live Activity needs it.
    private func saveWidgetArt(_ title: Title) async {
        guard WatchSession.shared.state?.id != title.id, let url = TMDB.imageURL(title.posterPath, .hero) else { return }
        await WatchSession.shared.savePoster(url, id: title.id, width: 600)
    }

    /// The programme starts now in the evening; earlier in the day it waits for doors at eight.
    static func doors(now: Date = .now) -> Date {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        guard hour >= 5, hour < 19 else { return now }
        return cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
    }

    private func startTimes() -> [Date] {
        var t = doors
        return programme.map { slot in defer { t += TimeInterval(slot.minutes * 60) }; return t }
    }

    private func finish(_ slot: Slot) {
        switch slot {
        case .episode(let u):
            Store.shared.setWatched([EpisodeKey(season: u.episode.seasonNumber, episode: u.episode.episodeNumber)], watched: true, show: u.show, runtime: u.runtime)
        case .film(let f), .pick(let f):
            Store.shared.track(f.title, status: .seen, runtime: f.runtime)
        case .free, .intermission, .headOut, .outing: break
        }
        Haptics.success()
    }

    private func openSearch() {
        guard let tabs = tabBarController else { return }
        tabs.selectedTab = tabs.tabs.first { $0 is UISearchTab }
    }

    // MARK: Collection

    /// The hero's pages: every title on tonight's programme, in order. A marathon can play one show twice, hence `nth`.
    private var heroPages: [TonightHeroCell.Page] {
        var seen: [Title: Int] = [:]
        return zip(programme, startTimes()).compactMap { slot, starts in
            guard let title = slot.title else { return nil }
            defer { seen[title, default: 0] += 1 }
            return .init(key: .init(title: title, nth: seen[title, default: 0]), slot: slot, starts: starts)
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, env in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .hero, nil:
                // One fixed height, so the page doesn't jump as the hero slides between titles.
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(env.container.effectiveContentSize.width * 1.5))
                let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                section.contentInsets.bottom = 28
                return section
            case .night: return Shelf.feature(height: (env.container.effectiveContentSize.width - Shelf.margin * 2) * 9 / 16)
            case .upcoming: return Shelf.posters(captions: 2)
            case .watchlist, .trending: return Shelf.posters()
            }
        }
    }

    private func configureDataSource() {
        let heroReg = UICollectionView.CellRegistration<TonightHeroCell, Item> { [unowned self] cell, _, _ in
            cell.heading.text = marathon?.name ?? "Tonight"
            cell.onPrimary = { [weak self] slot in self?.primary(slot) }
            cell.onDone = { [weak self] slot in self?.finish(slot) }
            cell.onOpen = { [weak self] title in
                // Tapping tonight's night out goes to the night, not the film.
                if let slot = self?.programme.first(where: { $0.title == title }), case .outing = slot { self?.primary(slot) } else { self?.openDetail(title) { nil } }
            }
            cell.onSettings = { [weak self] in self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true) }
            cell.onTime = { [weak self] in self?.timeFit() }
            if planned { cell.show(heroPages, suggestion: trending.first) }
        }
        let nightReg = UICollectionView.CellRegistration<WideLockup, Item> { cell, _, item in
            guard case .night(let uuid) = item, let night = Store.shared.night(uuid: uuid) else { return }
            Task { await HeroView.prepare(night.title) } // so the night's page opens on its finished art
            let when = (night.showtime ?? .now).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let time = (night.showtime ?? .now).formatted(date: .omitted, time: .shortened)
            cell.configure(.init(backdrop: TMDB.imageURL(night.backdropPath ?? night.posterPath, .backdrop), title: night.name ?? "",
                                 meta: "\(when) · Showtime \(time)" + (night.cinema.map { " · \($0)" } ?? ""), badge: night.status().label))
        }
        let posterReg = UICollectionView.CellRegistration<PosterLockup, Item> { cell, _, item in
            switch item {
            case .trending(let t), .watchlist(let t): cell.configure(t)
            case .upcoming(let u): cell.configure(u.title, caption: u.date.formatted(.dateTime.day().month(.abbreviated)), detail: u.label)
            default: break
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .night: header.configure("Movie Nights") { [weak self] in self?.openTab("nights") }
            case .watchlist: header.configure("Your Watchlist") { [weak self] in self?.openTab("stash") }
            case .upcoming: header.configure("Coming Soon")
            case .trending: header.configure("Everyone's Watching")
            default: header.configure("")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .hero: cv.dequeueConfiguredReusableCell(using: heroReg, for: indexPath, item: item)
            case .night: cv.dequeueConfiguredReusableCell(using: nightReg, for: indexPath, item: item)
            case .upcoming, .trending, .watchlist: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero]); snap.appendItems([.hero])
        let tonight = Store.shared.tonightsNight()?.uuid
        if let next = Store.shared.nights().first(where: { $0.status() != .creditsRolled && $0.uuid != tonight }), let uuid = next.uuid {
            snap.appendSections([.night]); snap.appendItems([.night(uuid)])
        }
        let picked = Set(programme.compactMap(\.title))
        let ready = Store.shared.all(.watchlist).map(\.title).filter { !picked.contains($0) && ($0.date.map { DateText.isPast($0) } ?? true) }
        if !ready.isEmpty { snap.appendSections([.watchlist]); snap.appendItems(ready.map(Item.watchlist)) }
        if !upcoming.isEmpty { snap.appendSections([.upcoming]); snap.appendItems(upcoming.prefix(10).map(Item.upcoming)) }
        if programme.isEmpty, !trending.isEmpty { snap.appendSections([.trending]); snap.appendItems(trending.map(Item.trending)) }
        snap.reconfigureItems([.hero])
        dataSource.apply(snap, animatingDifferences: !UIAccessibility.isReduceMotionEnabled)
    }

    // MARK: Actions

    /// The hero's white button: start a film on the clock, open an episode, or head to the cinema.
    private func primary(_ slot: Slot?) {
        Haptics.tap()
        switch slot {
        case .film(let f), .pick(let f):
            Task {
                let detail = try? await TMDB.shared.detail(f.title.id, .movie)
                let stinger = (detail?.midCredits ?? false) || (detail?.afterCredits ?? false)
                withPass { Task { await WatchSession.shared.start(f.title, runtime: f.runtime, from: f.position, stinger: stinger) } }
            }
        case .episode(let u): navigationController?.pushViewController(EpisodeViewController(show: u.show, episode: u.episode), animated: true)
        case .outing(let o): if let night = Store.shared.night(uuid: o.uuid) { navigationController?.pushViewController(NightViewController(night: night), animated: true) }
        case .free, .intermission, .headOut, nil: openSearch()
        }
    }

    /// I've Got…: everything you could watch next, for the sheet to fit to the time you have.
    private func timeFit() {
        Haptics.tap()
        var options: [TimeFitViewController.Option] = []
        for f in Store.shared.all(.watching) where f.mediaType == .movie && f.runtime > 0 {
            options.append(.init(title: f.title, kind: .finish, pieces: [max(Int(f.runtime) - Int(f.position) / 60, 1)]))
        }
        for u in upNext {
            // Later episodes are guessed at the show's usual length.
            let each = u.runtime ?? 45
            options.append(.init(title: u.show, kind: .episodes(u.episode), pieces: [max(each - u.position / 60, 1)] + Array(repeating: each, count: min(max(u.remaining - 1, 0), 12))))
        }
        for f in Store.shared.all(.watchlist) where f.mediaType == .movie && f.runtime > 0 && (f.releaseDate.map { DateText.isPast($0) } ?? true) {
            options.append(.init(title: f.title, kind: .watchlist, pieces: [Int(f.runtime)]))
        }
        let sheet = TimeFitViewController(options: options, untilLightsUp: Int(lightsUp.timeIntervalSinceNow / 60)) { [weak self] option in
            guard let self else { return }
            if case .episodes(let e) = option.kind {
                navigationController?.pushViewController(EpisodeViewController(show: option.title, episode: e), animated: true)
            } else {
                openDetail(option.title) { nil }
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        nav.navigationBar.prefersLargeTitles = true
        nav.sheetPresentationController?.detents = [.medium(), .large()]
        nav.sheetPresentationController?.prefersGrabberVisible = true
        present(nav, animated: true)
    }

    private func openTab(_ identifier: String) {
        guard let tabs = tabBarController else { return }
        tabs.selectedTab = tabs.tabs.first { $0.identifier == identifier }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .hero
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        let title: Title
        switch item {
        case .night(let uuid):
            guard let night = Store.shared.night(uuid: uuid) else { return }
            navigationController?.pushViewController(NightViewController(night: night), animated: true)
            return
        case .upcoming(let u): title = u.title
        case .trending(let t), .watchlist(let t): title = t
        case .hero: return
        }
        Haptics.tap()
        openDetail(title) { [weak self] in
            self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        switch indexPaths.first.flatMap({ dataSource.itemIdentifier(for: $0) }) {
        case .trending(let t), .watchlist(let t): return titleMenu(t)
        case .upcoming(let u): return titleMenu(u.title)
        default: return nil
        }
    }
}

// MARK: - Hero

/// The top of Tonight: everything on the programme, big, one title to a page. The dots fill as each
/// page's time runs out, the way the TV app's hero does, and stop whenever you're holding or reading it.
final class TonightHeroCell: UICollectionViewCell, UICollectionViewDelegate, UIPageControlTimerProgressDelegate {
    nonisolated struct Key: Hashable { let title: Title?; let nth: Int }
    struct Page { let key: Key; let slot: TonightViewController.Slot; let starts: Date }

    var onPrimary: ((TonightViewController.Slot?) -> Void)?
    var onDone: ((TonightViewController.Slot) -> Void)?
    var onOpen: ((Title) -> Void)?
    var onSettings: (() -> Void)?
    var onTime: (() -> Void)?
    /// False while another screen is in front.
    var onScreen = true { didSet { updateTimer() } }
    let heading = UILabel.make(Theme.text(.largeTitle, weight: .bold))

    private let settings = CapsuleButton.circle("gearshape", label: "Settings")
    private let time = CapsuleButton.circle("hourglass", label: "I've got…")
    private let control = UIPageControl()
    private let timer = UIPageControlTimerProgress(preferredDuration: 8)
    private let pager: UICollectionView
    private var data: UICollectionViewDiffableDataSource<Int, Key>!
    private var pages: [Key: Page] = [:]
    private var suggestion: Title?
    private var dragging = false, menuOpen = false
    /// The pager is on its way somewhere by itself, so its position shouldn't move the dots.
    private var autoScrolling = false

    override init(frame: CGRect) {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
        let section = NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [.init(layoutSize: size)]))
        // Left automatic, a sideways pager keeps its pages out of the status bar's safe area.
        section.contentInsetsReference = .none
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .horizontal
        pager = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section, configuration: config))
        super.init(frame: frame)

        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.backgroundColor = .clear
        pager.delegate = self
        contentView.addSubview(pager)
        pager.pin(to: contentView)
        let page = UICollectionView.CellRegistration<TonightHeroPageCell, Key> { [weak self] cell, _, key in
            guard let self else { return }
            if let page = pages[key] { cell.configure(page.slot, starts: page.starts) } else { cell.configureEmpty(suggestion) }
            cell.onPrimary = { [weak self] in self?.onPrimary?(self?.pages[key]?.slot) }
            cell.onDone = { [weak self] in if let slot = self?.pages[key]?.slot { self?.onDone?(slot) } }
            cell.onOpen = { [weak self] in if let slot = self?.pages[key]?.slot, let title = slot.title { self?.onOpen?(title) } }
            cell.onMenu = { [weak self] open in self?.menuOpen = open; self?.updateTimer() }
        }
        data = UICollectionViewDiffableDataSource(collectionView: pager) { cv, indexPath, key in
            cv.dequeueConfiguredReusableCell(using: page, for: indexPath, item: key)
        }

        heading.accessibilityTraits = .header
        control.hidesForSinglePage = true
        control.pageIndicatorTintColor = UIColor(white: 1, alpha: 0.4)
        control.currentPageIndicatorTintColor = .white
        control.addAction(UIAction { [weak self] _ in self?.go(to: self?.control.currentPage ?? 0) }, for: .valueChanged)
        timer.resetsToInitialPageAfterEnd = true
        timer.delegate = self
        // Pages that move by themselves are out for anyone who's asked for less motion or is using VoiceOver.
        if !UIAccessibility.isReduceMotionEnabled && !UIAccessibility.isVoiceOverRunning { control.progress = timer }

        [heading, time, settings, control].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 62),
            heading.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Shelf.margin),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -12),
            time.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            time.trailingAnchor.constraint(equalTo: settings.leadingAnchor, constant: -10),
            settings.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            settings.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Shelf.margin),
            control.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            control.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
        settings.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .primaryActionTriggered)
        time.addAction(UIAction { [weak self] _ in self?.onTime?() }, for: .primaryActionTriggered)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ new: [Page], suggestion: Title?) {
        self.suggestion = suggestion
        pages = Dictionary(uniqueKeysWithValues: new.map { ($0.key, $0) })
        let keys = new.isEmpty ? [Key(title: nil, nth: 0)] : new.map(\.key)
        let existing = Set(data.snapshot().itemIdentifiers)
        var snap = NSDiffableDataSourceSnapshot<Int, Key>()
        snap.appendSections([0])
        snap.appendItems(keys)
        snap.reconfigureItems(keys.filter(existing.contains))
        data.apply(snap, animatingDifferences: !existing.isEmpty && !UIAccessibility.isReduceMotionEnabled)
        control.numberOfPages = keys.count
        updateTimer()
        Task { for page in new { if let title = page.slot.title { await HeroView.prepare(title) } } }
    }

    private func updateTimer() {
        if onScreen && !dragging && !menuOpen { timer.resumeTimer() } else { timer.pauseTimer() }
    }

    private func go(to page: Int) {
        let x = CGFloat(page) * pager.bounds.width
        guard pager.contentOffset.x != x else { return }
        autoScrolling = true
        pager.setContentOffset(CGPoint(x: x, y: 0), animated: true)
    }

    func pageControlTimerProgress(_ progress: UIPageControlTimerProgress, shouldAdvanceToPage page: Int) -> Bool {
        go(to: page)
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let key = data.itemIdentifier(for: indexPath) else { return }
        if let title = key.title ?? suggestion { Haptics.tap(); onOpen?(title) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !autoScrolling, scrollView.bounds.width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        if page != control.currentPage { control.currentPage = page }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        autoScrolling = false
        dragging = true
        updateTimer()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settled() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settled() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { autoScrolling = false }

    private func settled() {
        dragging = false
        updateTimer()
    }
}

/// A round glass button that opens a menu and says when it has.
private final class MenuCircleButton: UIButton {
    var onMenu: ((Bool) -> Void)?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onMenu?(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onMenu?(false)
    }
}

/// One title on the hero, with its main button and a menu for the rest, as in the TV app.
final class TonightHeroPageCell: UICollectionViewCell {
    var onPrimary: (() -> Void)?
    var onDone: (() -> Void)?
    var onOpen: (() -> Void)?
    var onMenu: ((Bool) -> Void)? { didSet { more.onMenu = onMenu } }
    private let hero = HeroView()
    private let primary = CapsuleButton.primary("Resume", image: "play.fill")
    private let more = MenuCircleButton()
    /// What this page showed last, so the next episode of the same show fades in rather than snapping.
    private var current: TonightViewController.Slot?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(hero)
        hero.pin(to: contentView)
        hero.contentBottom.constant = -48
        more.configuration = CapsuleButton.circle("ellipsis", label: "").configuration
        more.accessibilityLabel = "More"
        more.showsMenuAsPrimaryAction = true
        NSLayoutConstraint.activate([more.widthAnchor.constraint(equalToConstant: 44), more.heightAnchor.constraint(equalToConstant: 44)])
        let buttons = UIStackView(arrangedSubviews: [primary, more])
        buttons.spacing = 12
        buttons.alignment = .center
        primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        hero.content.addArrangedSubview(buttons)
        primary.addAction(UIAction { [weak self] _ in self?.onPrimary?() }, for: .primaryActionTriggered)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ slot: TonightViewController.Slot, starts: Date) {
        guard let title = slot.title else { return }
        let nextUp = current?.title == title && current != slot
        current = slot
        guard nextUp else { return fill(slot, title: title, starts: starts) }
        UIView.transition(with: hero, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]) {
            self.fill(slot, title: title, starts: starts)
        }
    }

    private func fill(_ slot: TonightViewController.Slot, title: Title, starts: Date) {
        let now = starts <= .now
        let ends = starts + TimeInterval(slot.minutes * 60)
        let timing = now ? "Done by \(ends.formatted(date: .omitted, time: .shortened))" : "Starts \(starts.formatted(date: .omitted, time: .shortened))"
        var meta: String
        var watched = "Mark as Watched"
        switch slot {
        case .film(let f):
            meta = f.position >= 60 ? "Film · \(DateText.runtime(slot.minutes)) left" : "Film · \(DateText.runtime(f.runtime))"
            primary.configuration?.title = f.position >= 60 ? "Resume" : "Start Watching"
            primary.configuration?.image = UIImage(systemName: "play.fill")
        case .pick(let f):
            meta = "From your watchlist · \(DateText.runtime(f.runtime))"
            primary.configuration?.title = "Start Watching"
            primary.configuration?.image = UIImage(systemName: "play.fill")
        case .episode(let u):
            meta = "S\(u.episode.seasonNumber), E\(u.episode.episodeNumber) · " + (u.position >= 60 ? "\(DateText.runtime(slot.minutes)) left" : u.episode.name)
            primary.configuration?.title = (u.position >= 60 ? "Resume" : "Start") + " S\(u.episode.seasonNumber), E\(u.episode.episodeNumber)"
            primary.configuration?.image = UIImage(systemName: "play.fill")
            watched = "Mark S\(u.episode.seasonNumber), E\(u.episode.episodeNumber) as Watched"
        case .outing(let o):
            meta = "Movie Night · Showtime \(starts.formatted(date: .omitted, time: .shortened))" + (o.place.map { "\n\($0)" } ?? "")
            primary.configuration?.title = "Your Night Out"
            primary.configuration?.image = UIImage(systemName: "person.2.fill")
        case .free, .intermission, .headOut: return
        }
        if case .outing = slot { more.isHidden = true } else {
            meta += " · " + timing
            more.isHidden = false
            more.menu = UIMenu(children: [
                UIAction(title: watched, image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in self?.onDone?() },
                UIAction(title: title.mediaType == .tv ? "Go to Show" : "Go to Film", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.onOpen?() },
            ])
        }
        hero.show(title, meta: meta)
    }

    /// Nothing in progress: lead with something people are watching and a way to find more.
    func configureEmpty(_ suggestion: Title?) {
        current = nil
        primary.configuration?.title = "Find Something to Watch"
        primary.configuration?.image = UIImage(systemName: "magnifyingglass")
        more.isHidden = true
        if let suggestion {
            hero.show(suggestion, meta: "Nothing on tonight yet. Add a film or start a show and tonight plans itself.")
        } else {
            hero.name.text = "Nothing on tonight, yet"
            hero.meta.text = "Add a film or start a show and tonight plans itself."
        }
    }
}
