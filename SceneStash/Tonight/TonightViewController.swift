import UIKit
import WidgetKit

/// Tonight's programme: what you're in the middle of, laid out on the clock from now until lights up.
final class TonightViewController: UIViewController, UICollectionViewDelegate {
    nonisolated struct UpNext: Hashable { let show: Title; let episode: Episode; let remaining: Int; let runtime: Int? }
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
            case .episode(let u): u.runtime ?? 45
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
    nonisolated private enum Section: Hashable { case hero, programme, night, watchlist, upcoming, trending }
    nonisolated private enum Item: Hashable { case hero, slot(Slot), night(String), watchlist(Title), upcoming(Upcoming), trending(Title) }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var details: [Int: TitleDetail] = [:]
    private var upNext: [UpNext] = []
    private var programme: [Slot] = []
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        clock?.invalidate()
    }

    private func tick() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers.filter { if case .slot = $0 { true } else { $0 == .hero } })
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
                next.append(UpNext(show: detail.title, episode: episode, remaining: Progress.remaining(seasons: seasons, watched: watched, aired: aired), runtime: episode.runtime ?? detail.runtime))
            }
            upNext = next
            programme = buildProgramme()
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
            let code: String
            switch slot {
            case .episode(let u): code = "S\(u.episode.seasonNumber) E\(u.episode.episodeNumber)"
            case .film(let f): code = "\(max(f.runtime - f.position / 60, 0))m left"
            case .outing(let o): code = o.place ?? "Night out"
            default: code = DateText.runtime(slot.minutes)
            }
            snap.programme.append(.init(id: title.id, name: title.name, code: code, start: start, tint: tint))
        }
        if let next = upcoming.first(where: { $0.label.contains("premiere") || $0.label == "In cinemas" }) ?? upcoming.first {
            snap.premiere = .init(id: next.title.id, name: next.title.name, label: next.label, date: next.date)
        }
        if let u = upNext.first, let detail = details[u.show.id] {
            let season = u.episode.seasonNumber
            let count = detail.mainSeasons.first { $0.seasonNumber == season }?.episodeCount ?? 0
            let watched = Store.shared.watched(show: detail.id)
            let holes = (1...max(count, 1)).map { e in
                watched.contains(EpisodeKey(season: season, episode: e)) ? 1 : e == u.episode.episodeNumber ? 2 : 0
            }
            snap.card = .init(id: detail.id, name: detail.name, season: season, holes: count == 0 ? [] : holes, left: u.remaining)
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
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

    /// What the page leads with: the first title on tonight's programme.
    private var featured: Slot? { programme.first { $0.title != nil } }

    private func start(of slot: Slot) -> Date {
        programme.firstIndex(of: slot).map { startTimes()[$0] } ?? doors
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, env in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .hero, nil:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(760))
                let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                section.contentInsets.bottom = 28
                return section
            case .programme: return Shelf.wides(captions: 2)
            case .night: return Shelf.feature(height: (env.container.effectiveContentSize.width - Shelf.margin * 2) * 9 / 16)
            case .upcoming: return Shelf.posters(captions: 2)
            case .watchlist, .trending: return Shelf.posters()
            }
        }
    }

    private func configureDataSource() {
        let heroReg = UICollectionView.CellRegistration<TonightHeroCell, Item> { [unowned self] cell, _, _ in
            if let slot = featured {
                cell.configure(slot, starts: start(of: slot), lightsUp: lightsUp)
            } else {
                cell.configureEmpty(trending.first)
            }
            cell.onPrimary = { [weak self] in self?.primary() }
            cell.onDone = { [weak self] in if let slot = self?.featured { self?.finish(slot) } }
            cell.onSettings = { [weak self] in self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true) }
        }
        let slotReg = UICollectionView.CellRegistration<WideLockup, Item> { [unowned self] cell, _, item in
            guard case .slot(let slot) = item else { return }
            cell.configure(Self.lockup(slot, starts: start(of: slot)))
        }
        let nightReg = UICollectionView.CellRegistration<WideLockup, Item> { cell, _, item in
            guard case .night(let uuid) = item, let night = Store.shared.night(uuid: uuid) else { return }
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
            case .programme: header.configure(marathon?.name ?? "Up Next")
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
            case .slot: cv.dequeueConfiguredReusableCell(using: slotReg, for: indexPath, item: item)
            case .night: cv.dequeueConfiguredReusableCell(using: nightReg, for: indexPath, item: item)
            case .upcoming, .trending, .watchlist: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    /// A programme slot as a wide card: start time and what it is underneath.
    private static func lockup(_ slot: Slot, starts: Date) -> WideLockup.Model {
        let at = starts <= .now ? "Now" : starts.formatted(date: .omitted, time: .shortened)
        switch slot {
        case .episode(let u):
            return .init(backdrop: TMDB.imageURL(u.episode.stillPath, .backdrop) ?? TMDB.imageURL(u.show.backdropPath, .backdrop), title: u.show.name,
                         meta: "S\(u.episode.seasonNumber), E\(u.episode.episodeNumber) · \(u.runtime.map { "\($0)m" } ?? "Episode")", caption: at, detail: u.episode.name)
        case .film(let f):
            let left = max(f.runtime - f.position / 60, 0)
            return .init(backdrop: TMDB.imageURL(f.title.backdropPath, .backdrop), title: f.title.name,
                         meta: f.position >= 60 ? "\(DateText.runtime(left)) left" : DateText.runtime(f.runtime),
                         progress: f.position >= 60 ? Double(f.position) / Double(max(f.runtime * 60, 1)) : nil, caption: at, detail: "Film")
        case .pick(let f):
            return .init(backdrop: TMDB.imageURL(f.title.backdropPath, .backdrop), title: f.title.name, meta: DateText.runtime(f.runtime),
                         caption: at, detail: "From your watchlist")
        case .outing(let o):
            return .init(backdrop: TMDB.imageURL(o.title.backdropPath, .backdrop), title: o.title.name, meta: "Movie night", badge: "Booked",
                         caption: at, detail: o.place)
        case .free, .intermission, .headOut:
            return .init(backdrop: nil, title: "")
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero]); snap.appendItems([.hero])
        // The rest of the programme as a shelf; gaps and intermissions show as times, not cards.
        let rest = programme.filter { $0.title != nil && $0 != featured }
        if !rest.isEmpty { snap.appendSections([.programme]); snap.appendItems(rest.map(Item.slot)) }
        let tonight = Store.shared.tonightsNight()?.uuid
        if let next = Store.shared.nights().first(where: { $0.status() != .creditsRolled && $0.uuid != tonight }), let uuid = next.uuid {
            snap.appendSections([.night]); snap.appendItems([.night(uuid)])
        }
        let picked = Set(programme.compactMap(\.title))
        let ready = Store.shared.all(.watchlist).map(\.title).filter { !picked.contains($0) && ($0.date.map { DateText.isPast($0) } ?? true) }
        if !ready.isEmpty { snap.appendSections([.watchlist]); snap.appendItems(ready.map(Item.watchlist)) }
        if !upcoming.isEmpty { snap.appendSections([.upcoming]); snap.appendItems(upcoming.prefix(10).map(Item.upcoming)) }
        if programme.isEmpty, !trending.isEmpty { snap.appendSections([.trending]); snap.appendItems(trending.map(Item.trending)) }
        snap.reconfigureItems(snap.itemIdentifiers.filter { if case .slot = $0 { true } else { $0 == .hero } })
        dataSource.apply(snap, animatingDifferences: !UIAccessibility.isReduceMotionEnabled)
    }

    // MARK: Actions

    /// The hero's white button: start a film on the clock, open a show, or head to the cinema.
    private func primary() {
        Haptics.tap()
        switch featured {
        case .film(let f), .pick(let f):
            Task {
                let detail = try? await TMDB.shared.detail(f.title.id, .movie)
                let stinger = (detail?.midCredits ?? false) || (detail?.afterCredits ?? false)
                withPass { Task { await WatchSession.shared.start(f.title, runtime: f.runtime, from: f.position, stinger: stinger) } }
            }
        case .episode(let u): openDetail(u.show) { nil }
        case .outing(let o): if let night = Store.shared.night(uuid: o.uuid) { navigationController?.pushViewController(NightViewController(night: night), animated: true) }
        case .free, .intermission, .headOut, nil: openSearch()
        }
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
        case .slot(.outing(let o)):
            guard let night = Store.shared.night(uuid: o.uuid) else { return }
            navigationController?.pushViewController(NightViewController(night: night), animated: true)
            return
        case .night(let uuid):
            guard let night = Store.shared.night(uuid: uuid) else { return }
            navigationController?.pushViewController(NightViewController(night: night), animated: true)
            return
        case .slot(let s): guard let t = s.title else { return }; title = t
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
        case .slot(let s):
            guard let t = s.title else { return nil }
            if case .outing = s { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(title: t.name, children: [UIAction(title: "Mark as Watched", image: UIImage(systemName: "checkmark.circle")) { _ in self?.finish(s) }])
            }
        default: return nil
        }
    }
}

// MARK: - Hero

/// The top of Tonight: whatever leads the programme, big, with Resume and Mark as Watched.
final class TonightHeroCell: UICollectionViewCell {
    var onPrimary: (() -> Void)?
    var onDone: (() -> Void)?
    var onSettings: (() -> Void)?
    private let hero = HeroView()
    private let heading = UILabel.make(Theme.text(.largeTitle, weight: .bold))
    private let settings = CapsuleButton.circle("gearshape", label: "Settings")
    private let primary = CapsuleButton.primary("Resume", image: "play.fill")
    private let done = CapsuleButton.circle("checkmark", label: "Mark as Watched")

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(hero)
        hero.pin(to: contentView)
        heading.text = "Tonight"
        heading.accessibilityTraits = .header
        let top = UIStackView(arrangedSubviews: [heading, UIView(), settings])
        top.alignment = .center
        contentView.addSubview(top)
        top.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 62),
            top.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Shelf.margin),
            top.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Shelf.margin),
        ])
        let buttons = UIStackView(arrangedSubviews: [primary, done])
        buttons.spacing = 12
        buttons.alignment = .center
        primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        hero.content.addArrangedSubview(buttons)
        primary.addAction(UIAction { [weak self] _ in self?.onPrimary?() }, for: .primaryActionTriggered)
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .primaryActionTriggered)
        settings.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .primaryActionTriggered)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// What the hero showed last, so a new episode or title (you just finished one) fades across instead of snapping.
    private var current: TonightViewController.Slot?

    func configure(_ slot: TonightViewController.Slot, starts: Date, lightsUp: Date) {
        guard let title = slot.title else { return }
        let changed = current != nil && current != slot
        current = slot
        guard changed else { return fill(slot, title: title, starts: starts) }
        UIView.transition(with: hero, duration: 0.45, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.fill(slot, title: title, starts: starts)
        }
    }

    private func fill(_ slot: TonightViewController.Slot, title: Title, starts: Date) {
        let now = starts <= .now
        let ends = starts + TimeInterval(slot.minutes * 60)
        let timing = now ? "Done by \(ends.formatted(date: .omitted, time: .shortened))" : "Starts \(starts.formatted(date: .omitted, time: .shortened))"
        var meta: String
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
            meta = "S\(u.episode.seasonNumber), E\(u.episode.episodeNumber) · \(u.episode.name)"
            primary.configuration?.title = "Start S\(u.episode.seasonNumber), E\(u.episode.episodeNumber)"
            primary.configuration?.image = UIImage(systemName: "play.fill")
        case .outing(let o):
            meta = "Movie Night · Showtime \(starts.formatted(date: .omitted, time: .shortened))" + (o.place.map { "\n\($0)" } ?? "")
            primary.configuration?.title = "Your Night Out"
            primary.configuration?.image = UIImage(systemName: "person.2.fill")
        case .free, .intermission, .headOut: return
        }
        if case .outing = slot {} else { meta += " · " + timing }
        done.isHidden = { if case .outing = slot { true } else { false } }()
        hero.show(title, meta: meta)
    }

    /// Nothing in progress: lead with something people are watching and a way to find more.
    func configureEmpty(_ suggestion: Title?) {
        current = nil
        primary.configuration?.title = "Find Something to Watch"
        primary.configuration?.image = UIImage(systemName: "magnifyingglass")
        done.isHidden = true
        if let suggestion {
            hero.show(suggestion, meta: "Nothing on tonight yet. Add a film or start a show and tonight plans itself.")
        } else {
            hero.name.text = "Nothing on tonight, yet"
            hero.meta.text = "Add a film or start a show and tonight plans itself."
        }
    }
}
