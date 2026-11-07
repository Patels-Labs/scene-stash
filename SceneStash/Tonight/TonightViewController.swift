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
    nonisolated private enum Section: Hashable { case header, programme, watchlist, upcoming, trending }
    nonisolated private enum Item: Hashable { case header, slot(Slot), watchlist(Title), upcoming(Upcoming), trending(Title) }

    private let glow = GlowView()
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
            if programme.isEmpty { glow.show(TMDB.imageURL(trending.first?.posterPath, .poster)) }
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
        snap.reconfigureItems(snap.itemIdentifiers.filter { if case .upcoming = $0 { false } else if case .trending = $0 { false } else { true } })
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
            glow.show(TMDB.imageURL(programme.first?.title?.posterPath ?? trending.first?.posterPath, .poster))
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

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            let list = { (insets: NSDirectionalEdgeInsets, spacing: CGFloat) -> NSCollectionLayoutSection in
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
                s.contentInsets = insets
                s.interGroupSpacing = spacing
                return s
            }
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .header: return list(.init(top: 8, leading: 20, bottom: 22, trailing: 20), 0)
            case .programme: return list(.init(top: 0, leading: 0, bottom: 44, trailing: 20), 8)
            case .upcoming:
                let s = list(.init(top: 8, leading: 20, bottom: 40, trailing: 20), 0)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            default: return Layouts.posterRow()
            }
        }
    }

    private func configureDataSource() {
        let headerCellReg = UICollectionView.CellRegistration<ProgrammeHeaderCell, Item> { [unowned self] cell, _, _ in
            let used = programme.reduce(0) { $0 + $1.minutes }
            cell.configure(doors: doors, lightsUp: lightsUp, booked: used, slots: programme.filter { $0.title != nil }.count,
                           empty: Store.shared.all().isEmpty, marathon: marathon?.name)
            cell.onDiscover = { [weak self] in self?.openSearch() }
        }
        let slotReg = UICollectionView.CellRegistration<ProgrammeCell, Item> { [unowned self] cell, _, item in
            guard case .slot(let slot) = item, let i = programme.firstIndex(of: slot) else { return }
            cell.configure(slot, start: startTimes()[i], isNow: i == 0 && doors <= .now)
            cell.onTorn = { [weak self] in self?.finish(slot) }
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
            case .header: cv.dequeueConfiguredReusableCell(using: headerCellReg, for: indexPath, item: item)
            case .slot: cv.dequeueConfiguredReusableCell(using: slotReg, for: indexPath, item: item)
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
        snap.appendSections([.header]); snap.appendItems([.header])
        if !programme.isEmpty { snap.appendSections([.programme]); snap.appendItems(programme.map(Item.slot)) }
        let picked = Set(programme.compactMap(\.title))
        let ready = Store.shared.all(.watchlist).map(\.title).filter { !picked.contains($0) && ($0.date.map { DateText.isPast($0) } ?? true) }
        if !ready.isEmpty { snap.appendSections([.watchlist]); snap.appendItems(ready.map(Item.watchlist)) }
        if !upcoming.isEmpty { snap.appendSections([.upcoming]); snap.appendItems(upcoming.prefix(8).map(Item.upcoming)) }
        if programme.isEmpty, !trending.isEmpty { snap.appendSections([.trending]); snap.appendItems(trending.map(Item.trending)) }
        snap.reconfigureItems(snap.itemIdentifiers.filter { if case .slot = $0 { true } else { $0 == .header } })
        dataSource.apply(snap, animatingDifferences: !UIAccessibility.isReduceMotionEnabled)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        let title: Title
        switch item {
        case .slot(.free): openSearch(); return
        case .slot(.intermission), .slot(.headOut): return
        case .slot(.outing(let o)):
            guard let night = Store.shared.night(uuid: o.uuid) else { return }
            Haptics.tap()
            navigationController?.pushViewController(NightViewController(night: night), animated: true)
            return
        case .slot(let s): guard let t = s.title else { return }; title = t
        case .upcoming(let u): title = u.title
        case .trending(let t), .watchlist(let t): title = t
        case .header: return
        }
        Haptics.tap()
        openDetail(title) { [weak self] in
            self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) }.map { ($0 as? ProgrammeCell)?.card ?? $0 }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        switch indexPaths.first.flatMap({ dataSource.itemIdentifier(for: $0) }) {
        case .trending(let t), .watchlist(let t): return titleMenu(t)
        case .slot(let s): return s.title.map(titleMenu)
        default: return nil
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        glow.transform = CGAffineTransform(translationX: 0, y: -max(y, 0) * 0.5)
    }
}

// MARK: - Cells

/// Date and a live clock, then how long you've got: the whole evening in one line.
final class ProgrammeHeaderCell: UICollectionViewCell {
    var onDiscover: (() -> Void)?
    private let date = UILabel.make(Theme.label(), Theme.secondary)
    private let time = UILabel.make(Theme.label(.caption2, weight: .bold))
    private let dot = UIView()
    private let headline = UILabel.make(Theme.display(66, weight: .black), Theme.text, lines: 0)
    private let body = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)
    private let button = PillButton("Find something to watch", image: "sparkle.magnifyingglass")

    override init(frame: CGRect) {
        super.init(frame: frame)
        dot.backgroundColor = UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1)
        dot.layer.cornerRadius = 3
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let clock = UIStackView(arrangedSubviews: [dot, time])
        clock.alignment = .center
        clock.spacing = 6
        let top = UIStackView(arrangedSubviews: [date, UIView(), clock])
        top.alignment = .center
        button.addAction(UIAction { [weak self] _ in self?.onDiscover?() }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [top, headline, body, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(18, after: top)
        stack.setCustomSpacing(22, after: body)
        contentView.addSubview(stack)
        stack.pin(to: contentView)
        headline.accessibilityTraits = .header
        if !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 1, delay: 0, options: [.autoreverse, .repeat, .allowUserInteraction]) { self.dot.alpha = 0.25 }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(doors: Date, lightsUp: Date, booked: Int, slots: Int, empty: Bool, marathon: String?) {
        let now = Date.now
        date.setCaps(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        time.setCaps(now.formatted(.dateTime.hour().minute()), kern: 1.2)
        button.isHidden = !empty
        let left = max(Int(lightsUp.timeIntervalSince(now) / 60), 0)
        let line1: String, line2: String
        if empty {
            (line1, line2) = ("Nothing on", "tonight, yet.")
            body.text = "Stash a film or start a show, and tonight's programme builds itself here."
        } else if let marathon, slots > 0 {
            (line1, line2) = (DateText.runtime(booked), doors > now ? "starts \(doors.formatted(.dateTime.hour().minute()))" : "marathon day")
            body.text = "Today's stretch of \(marathon). Tear each stub as you go and the rest of the plan keeps up."
        } else if doors > now, slots > 0 {
            (line1, line2) = (DateText.runtime(booked), "on tonight")
            body.text = "Doors at \(doors.formatted(.dateTime.hour().minute())). Here's what's showing, from what you're in the middle of."
        } else {
            (line1, line2) = (DateText.runtime(left), "till lights up")
            if slots == 0 {
                body.text = "Nothing in progress. Pick something and it'll be waiting here, on the clock."
            } else if booked > left {
                body.text = "Tonight's programme runs \(DateText.runtime(booked)). Something will spill into tomorrow."
            } else {
                body.text = "Tonight's programme, from what you're in the middle of. Tear a stub when you're done."
            }
        }
        let text = NSMutableAttributedString(string: line1.uppercased() + "\n", attributes: [.foregroundColor: Theme.text])
        text.append(NSAttributedString(string: line2.uppercased(), attributes: [.foregroundColor: Theme.tertiary]))
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 0.86
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        headline.attributedText = text
    }
}

/// One slot on the programme: the start time in the gutter, a card as tall as the runtime, and a stub to tear.
final class ProgrammeCell: UICollectionViewCell {
    var onTorn: (() -> Void)?
    let card = CardView()
    private let time = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.tertiary)
    private let image = UIImageView()
    private let shade = CAGradientLayer()
    private let code = UILabel.make(Theme.label(.caption2, weight: .bold), UIColor(white: 1, alpha: 0.85))
    private let name = UILabel.make(Theme.display(40, weight: .black), Theme.text, lines: 0)
    private let sub = UILabel.make(Theme.text(.footnote), UIColor(white: 1, alpha: 0.82))
    private let strip = FilmStripView()
    private let stub = StubView()
    private let dashed = CAShapeLayer()
    private var height: NSLayoutConstraint!
    private var freeHeight: NSLayoutConstraint!
    private var shownID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.backgroundColor = Theme.surfaceHigh
        image.contentMode = .scaleAspectFill
        shade.startPoint = CGPoint(x: 0, y: 0.5)
        shade.endPoint = CGPoint(x: 1, y: 0.5)
        dashed.fillColor = nil
        dashed.strokeColor = UIColor(white: 1, alpha: 0.22).cgColor
        dashed.lineWidth = 1.5
        dashed.lineDashPattern = [5, 4]
        card.layer.addSublayer(dashed)
        card.onLayout = { [weak self] bounds in
            guard let self else { return }
            shade.frame = bounds
            dashed.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 17).cgPath
        }
        strip.frames = 14

        let textStack = UIStackView(arrangedSubviews: [name, sub, strip])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setCustomSpacing(10, after: sub)
        [image, code, textStack, stub].forEach { card.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        card.layer.insertSublayer(shade, above: image.layer)
        [time, card].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        // A minimum, so long titles grow the card instead of being clipped.
        height = card.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        height.priority = .init(999)
        freeHeight = card.heightAnchor.constraint(equalToConstant: 52)
        freeHeight.priority = .init(999)
        let content = card.layoutMarginsGuide
        card.directionalLayoutMargins = .init(top: 14, leading: 14, bottom: 14, trailing: 14)
        NSLayoutConstraint.activate([
            time.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            time.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            time.widthAnchor.constraint(equalToConstant: 52),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 76),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            height,
            image.topAnchor.constraint(equalTo: card.topAnchor),
            image.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            image.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stub.topAnchor.constraint(equalTo: card.topAnchor),
            stub.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stub.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stub.widthAnchor.constraint(equalToConstant: 52),
            code.topAnchor.constraint(equalTo: content.topAnchor),
            code.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            code.trailingAnchor.constraint(lessThanOrEqualTo: stub.leadingAnchor, constant: -12),
            textStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: stub.leadingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: code.bottomAnchor, constant: 6),
            strip.heightAnchor.constraint(equalToConstant: 22),
        ])
        // The backdrop and stub fill whatever height the text needs; they never set it.
        [image, stub].forEach { $0.setContentCompressionResistancePriority(.init(1), for: .vertical) }
        stub.onTorn = { [weak self] in self?.onTorn?() }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        stub.reset()
    }

    func configure(_ slot: TonightViewController.Slot, start: Date, isNow: Bool) {
        time.setCaps(isNow ? "Now" : start.formatted(.dateTime.hour().minute()), kern: 1)
        time.textColor = isNow ? UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1) : Theme.tertiary
        let isFree: Bool = { switch slot { case .free, .intermission, .headOut: true; default: false } }()
        // Cards are as tall as they run, within reason.
        height.constant = isFree ? 52 : min(max(CGFloat(slot.minutes) * 2.4, 124), 240)
        freeHeight.isActive = isFree
        card.directionalLayoutMargins.top = isFree ? 19 : 14
        [image, code, name, sub, stub].forEach { $0.isHidden = isFree }
        dashed.isHidden = !isFree
        card.backgroundColor = isFree ? .clear : Theme.surfaceHigh
        shade.isHidden = isFree
        strip.isHidden = true
        name.font = Theme.display(height.constant < 150 ? 32 : 42, weight: .black)

        switch slot {
        case .episode(let u):
            code.setCaps("S\(u.episode.seasonNumber) · E\(u.episode.episodeNumber) · \(u.runtime.map { "\($0) min" } ?? "Episode")", kern: 1.2)
            name.setDisplay(u.show.name.uppercased())
            sub.text = u.episode.name
            stub.set("Watched")
            show(TMDB.imageURL(u.episode.stillPath, .backdrop) ?? TMDB.imageURL(u.show.backdropPath, .backdrop), poster: u.show.posterPath, id: u.show.id)
            accessibilityLabel = "\(u.show.name), season \(u.episode.seasonNumber) episode \(u.episode.episodeNumber), \(u.episode.name)"
        case .film(let f):
            let left = max(f.runtime - f.position / 60, 0)
            code.setCaps(f.position >= 60 ? "Film · \(left) min left · from \(Self.clock(f.position))" : "Film · \(DateText.runtime(f.runtime))", kern: 1.2)
            name.setDisplay(f.title.name.uppercased())
            sub.text = nil
            strip.isHidden = false
            strip.value = Double(f.position) / Double(max(f.runtime * 60, 1))
            stub.set("Finished")
            show(TMDB.imageURL(f.title.backdropPath, .backdrop), poster: f.title.posterPath, id: f.title.id)
            accessibilityLabel = "\(f.title.name), \(left) minutes left"
        case .pick(let f):
            code.setCaps("From your watchlist · \(DateText.runtime(f.runtime))", kern: 1.2)
            name.setDisplay(f.title.name.uppercased())
            sub.text = "It fits before lights up."
            stub.set("Seen it")
            show(TMDB.imageURL(f.title.backdropPath, .backdrop), poster: f.title.posterPath, id: f.title.id)
            accessibilityLabel = "Suggestion from your watchlist: \(f.title.name)"
        case .free:
            code.isHidden = false
            code.setCaps("Time to spare · find a short", kern: 1.2)
            accessibilityLabel = "Time to spare. Find something short"
        case .intermission(let m):
            code.isHidden = false
            code.setCaps("Intermission · \(m) min", kern: 1.2)
            accessibilityLabel = "Intermission, \(m) minutes"
        case .headOut(let m):
            code.isHidden = false
            code.setCaps(m > 45 ? "Free, then head out · \(DateText.runtime(m))" : "Head out to the cinema · \(m) min", kern: 1.2)
            accessibilityLabel = "Head out to the cinema, \(m) minutes"
        case .outing(let o):
            code.setCaps("Night out · \(DateText.runtime(o.minutes))", kern: 1.2)
            name.setDisplay(o.title.name.uppercased())
            sub.text = o.place ?? "Cinema to be picked"
            show(TMDB.imageURL(o.title.backdropPath, .backdrop), poster: o.title.posterPath, id: o.title.id)
            accessibilityLabel = "Night out: \(o.title.name), \(o.place ?? "")"
        }
        // A night out ends itself when the credits roll; there's no stub to tear.
        if case .outing = slot { stub.isHidden = true }
        accessibilityCustomActions = isFree || stub.isHidden ? nil : [UIAccessibilityCustomAction(name: stub.accessibilityLabel ?? "Done") { [weak self] _ in
            self?.stub.tear(); return true
        }]
    }

    private func show(_ url: URL?, poster: String?, id: Int) {
        shownID = id
        image.setImage(url)
        applyShade(Theme.surfaceHigh)
        guard let p = TMDB.imageURL(poster, .poster) else { return }
        Task { [weak self] in
            guard let tint = await ImageLoader.shared.tint(for: p), let self, shownID == id else { return }
            applyShade(tint)
            strip.tint = tint
        }
    }

    /// The still sits under a wash of the poster's colour, darkest where the words are.
    private func applyShade(_ tint: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let deep = UIColor(hue: h, saturation: min(s * 1.1, 1), brightness: 0.22, alpha: 0.94)
        let mid = UIColor(hue: h, saturation: s, brightness: 0.45, alpha: 0.55)
        shade.colors = [deep.cgColor, mid.cgColor, mid.withAlphaComponent(0.25).cgColor]
        shade.locations = [0, 0.55, 1]
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, seconds % 3600 / 60)
    }

    override var isHighlighted: Bool { didSet { Spring.press(card, isHighlighted, scale: 0.97) } }
}

/// A plain view that reports its layout, for layers that follow its size.
final class CardView: UIView {
    var onLayout: ((CGRect) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(bounds) }
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
