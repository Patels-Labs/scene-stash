import UIKit

/// A title's page, Apple TV-style: tall art with its logo and the main buttons, then what you need to know,
/// and shelves of episodes, cast and more.
final class DetailViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case hero, progress, credits, rating, episodes, providers, cast, more }
    nonisolated private enum Item: Hashable {
        case hero, progress, credits, rating
        case episode(Episode), provider(Provider), cast(CastMember), title(Title)
    }

    private let item: Title
    private var detail: TitleDetail?
    private var selectedSeason: Int?
    private var seasonEpisodes: [Int: [Episode]] = [:]
    private var watched: Set<EpisodeKey> = []

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private let hero = HeroView()
    private let primary = CapsuleButton.primary("Start Watching", image: "play.fill")
    private let secondary = CapsuleButton.glass("Plan a Night Out", image: "person.2.fill")
    private let trailer = CapsuleButton.circle("play.rectangle", label: "Watch trailer")
    private let status = CapsuleButton.circle("plus", label: "Add to Watchlist")
    private let overview = UILabel.make(Theme.text(.subheadline), UIColor(white: 1, alpha: 0.72), lines: 3)
    private let info = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 2)

    init(title: Title) {
        item = title
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), menu: UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.moreMenu() ?? [])
        }]))

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        // The art runs up under the navigation bar, like the TV app.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        buildHero()
        configureDataSource()
        refreshHero()
        applySnapshot()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .watchChanged, object: nil)
    }

    // MARK: Loading

    private func load() {
        Task {
            do {
                let detail = try await TMDB.shared.detail(item.id, item.mediaType)
                self.detail = detail
                if detail.mediaType == .tv {
                    watched = Store.shared.watched(show: detail.id)
                    let next = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey)
                    selectedSeason = next?.season ?? detail.mainSeasons.first?.seasonNumber
                }
                refreshHero()
                applySnapshot()
                if let season = selectedSeason { loadSeason(season) }
            } catch {
                showError(error)
            }
        }
    }

    private func loadSeason(_ number: Int) {
        guard seasonEpisodes[number] == nil else { applySnapshot(); return }
        Task {
            guard let season = try? await TMDB.shared.season(show: item.id, number: number) else { return }
            seasonEpisodes[number] = season.episodes
            applySnapshot()
        }
    }

    private var seasonMap: [Int: Int] {
        Dictionary(uniqueKeysWithValues: (detail?.mainSeasons ?? []).map { ($0.seasonNumber, $0.episodeCount) })
    }
    private var airedKey: EpisodeKey? {
        detail?.lastEpisodeToAir.map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) }
    }
    private var nextEpisode: EpisodeKey? { Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey) }
    private var tracked: Tracked? { Store.shared.tracked(item.id, item.mediaType) }
    private var live: WatchSession.State? { WatchSession.shared.state.flatMap { $0.id == item.id ? $0 : nil } }

    // MARK: Hero

    private func buildHero() {
        hero.show(item, meta: nil)
        primary.widthAnchor.constraint(equalToConstant: 255).isActive = true
        secondary.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let row = UIStackView(arrangedSubviews: [secondary, trailer, status])
        row.spacing = 10
        row.alignment = .center
        overview.isUserInteractionEnabled = true
        overview.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleOverview)))
        overview.accessibilityHint = "Double tap to read more"
        [primary, row, overview, info].forEach(hero.content.addArrangedSubview)
        hero.content.setCustomSpacing(10, after: primary)
        hero.content.setCustomSpacing(18, after: row)
        hero.content.setCustomSpacing(8, after: overview)
        [overview, info].forEach { $0.widthAnchor.constraint(equalTo: hero.content.widthAnchor).isActive = true }

        primary.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .primaryActionTriggered)
        secondary.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            item.mediaType == .movie ? planNight() : withPass { self.planMarathon() }
        }, for: .primaryActionTriggered)
        trailer.addAction(UIAction { [weak self] _ in
            if let url = self?.detail?.trailerURL { UIApplication.shared.open(url) }
        }, for: .primaryActionTriggered)
        status.addAction(UIAction { [weak self] _ in self?.addToWatchlist() }, for: .primaryActionTriggered)
    }

    @objc private func toggleOverview() {
        overview.numberOfLines = overview.numberOfLines == 0 ? 3 : 0
        overview.accessibilityHint = overview.numberOfLines == 0 ? nil : "Double tap to read more"
        var snap = dataSource.snapshot()
        snap.reconfigureItems([.hero])
        dataSource.apply(snap, animatingDifferences: true)
    }

    private func refreshHero() {
        let d = detail
        var kind = [item.mediaType == .movie ? "Film" : "TV Show"]
        kind += (d?.genres.prefix(2).map(\.name) ?? [])
        hero.meta.text = kind.joined(separator: " · ")
        hero.meta.isHidden = false

        let tracked = tracked
        if item.mediaType == .movie {
            if let live {
                primary.configuration?.title = live.pausedAt == nil ? "Pause" : "Resume"
                primary.configuration?.image = UIImage(systemName: live.pausedAt == nil ? "pause.fill" : "play.fill")
            } else {
                let resume = (tracked?.position ?? 0) > 0 && tracked?.status != .seen
                primary.configuration?.title = resume ? "Resume" : "Start Watching"
                primary.configuration?.image = UIImage(systemName: "play.fill")
            }
            primary.isHidden = (d?.runtime ?? 0) == 0 && live == nil
            let planned = Store.shared.nights(for: item).contains { $0.status() != .creditsRolled }
            secondary.configuration?.title = planned ? "Your Night Out" : "Plan a Night Out"
            secondary.configuration?.image = UIImage(systemName: "person.2.fill")
            secondary.isHidden = false
        } else {
            if let next = nextEpisode {
                primary.configuration?.title = "Mark S\(next.season), E\(next.episode) Watched"
                primary.configuration?.image = UIImage(systemName: "checkmark")
                primary.isEnabled = true
            } else {
                primary.configuration?.title = watched.isEmpty ? "Not Out Yet" : "All Caught Up"
                primary.configuration?.image = nil
                primary.isEnabled = false
            }
            primary.isHidden = d == nil
            secondary.configuration?.title = "Plan a Marathon"
            secondary.configuration?.image = UIImage(systemName: "calendar")
            secondary.isHidden = d?.mainSeasons.isEmpty ?? true
        }
        trailer.isHidden = d?.trailerURL == nil

        if let tracked {
            status.configuration?.image = UIImage(systemName: "checkmark")
            status.configuration?.baseForegroundColor = Theme.accent
            status.accessibilityLabel = "In your library: \(tracked.status.label)"
            status.menu = statusMenu()
            status.showsMenuAsPrimaryAction = true
        } else {
            status.configuration?.image = UIImage(systemName: "plus")
            status.configuration?.baseForegroundColor = .white
            status.accessibilityLabel = "Add to Watchlist"
            status.menu = nil
            status.showsMenuAsPrimaryAction = false
        }

        overview.text = d?.overview.isEmpty == false ? d?.overview : item.overview
        overview.isHidden = overview.text?.isEmpty ?? true

        var bits: [String] = []
        if let year = d?.year ?? item.year { bits.append(year) }
        if item.mediaType == .movie {
            if let runtime = d?.runtime, runtime > 0 { bits.append(DateText.runtime(runtime)) }
        } else if let d {
            let seasons = d.mainSeasons.count
            if seasons > 0 { bits.append("\(seasons) season\(seasons == 1 ? "" : "s")") }
            let remaining = Progress.remaining(seasons: seasonMap, watched: watched, aired: airedKey)
            if let next = nextEpisode, !watched.isEmpty {
                bits.append("Up next S\(next.season), E\(next.episode) · \(remaining) to go")
            } else if nextEpisode == nil, let upcoming = d.nextEpisodeToAir?.airDate.flatMap(DateText.pretty) {
                bits.append("Next episode \(upcoming)")
            }
        }
        if let vote = d?.voteAverage ?? item.voteAverage, vote > 0 { bits.append("TMDB " + vote.formatted(.number.precision(.fractionLength(1)))) }
        let text = NSMutableAttributedString(string: bits.joined(separator: " · "), attributes: [.foregroundColor: Theme.secondary])
        if let d, d.midCredits || d.afterCredits {
            text.append(NSAttributedString(string: "  ● After-credits scene", attributes: [.foregroundColor: Theme.accent]))
        }
        info.attributedText = text
    }

    private func statusMenu() -> UIMenu {
        let title = detail?.title ?? item
        let current = tracked?.status
        var actions: [UIMenuElement] = TrackStatus.allCases.map { s in
            UIAction(title: s.label, image: UIImage(systemName: s.symbol), state: current == s ? .on : .off) { [weak self] _ in
                Store.shared.track(title, status: s, runtime: self?.detail?.runtime)
                if s == .seen, WatchSession.shared.isWatching(title.id) { Task { await WatchSession.shared.finish() } }
                Haptics.success()
            }
        }
        actions.append(UIAction(title: "Remove from Library", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            Store.shared.remove(title)
        })
        return UIMenu(children: actions)
    }

    private func moreMenu() -> [UIMenuElement] {
        var items: [UIMenuElement] = [UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share() }]
        if item.mediaType == .movie, detail?.collection != nil {
            items.append(UIAction(title: "Plan a Marathon of the Series", image: UIImage(systemName: "calendar")) { [weak self] _ in
                self?.withPass { self?.planMarathon() }
            })
        }
        return items
    }

    // MARK: Actions

    private func primaryTapped() {
        let title = detail?.title ?? item
        if item.mediaType == .tv {
            guard let next = nextEpisode else { return }
            Haptics.success()
            let runtime = seasonEpisodes[next.season]?.first { $0.episodeNumber == next.episode }?.runtime ?? detail?.runtime
            Store.shared.setWatched([next], watched: true, show: title, runtime: runtime)
            return
        }
        if let live {
            Task { live.pausedAt == nil ? await WatchSession.shared.pause() : await WatchSession.shared.resume() }
            return
        }
        guard let runtime = detail?.runtime, runtime > 0 else { return }
        let from = tracked?.status == .seen ? 0 : Int(tracked?.position ?? 0)
        let stinger = (detail?.midCredits ?? false) || (detail?.afterCredits ?? false)
        Haptics.tap()
        withPass { Task { await WatchSession.shared.start(title, runtime: runtime, from: from, stinger: stinger) } }
    }

    private func addToWatchlist() {
        guard tracked == nil else { return }
        Store.shared.track(detail?.title ?? item, status: .watchlist, runtime: detail?.runtime)
        Haptics.success()
    }

    /// Opens the night already planned for this film, or starts planning one.
    private func planNight() {
        Haptics.tap()
        if let upcoming = Store.shared.nights(for: item).first(where: { $0.status() != .creditsRolled }) {
            navigationController?.pushViewController(NightViewController(night: upcoming), animated: true)
            return
        }
        let form = NightFormViewController(title: detail?.title ?? item) { [weak self] night in
            self?.navigationController?.pushViewController(NightViewController(night: night), animated: true)
        }
        present(UINavigationController(rootViewController: form), animated: true)
    }

    /// A film series becomes a marathon of every released part; a show, the rest of the selected season.
    private func planMarathon() {
        guard let detail else { return }
        Haptics.tap()
        if item.mediaType == .movie, let series = detail.collection {
            Task {
                let parts = (try? await TMDB.shared.collection(series.id)) ?? []
                var runtimes: [Int: Int] = [:]
                await withTaskGroup(of: (Int, Int?).self) { group in
                    for part in parts { group.addTask { (part.id, try? await TMDB.shared.detail(part.id, .movie).runtime) } }
                    for await (id, runtime) in group { runtimes[id] = runtime }
                }
                // ponytail: unwatched parts only; rewatch marathons would need per-marathon progress.
                let pieces = parts.filter { Store.shared.tracked($0.id, .movie)?.status != .seen }
                    .map { Piece(id: $0.id, isEpisode: false, name: $0.name, detail: nil, poster: $0.posterPath, backdrop: $0.backdropPath, minutes: runtimes[$0.id] ?? 120) }
                guard !pieces.isEmpty else {
                    alert("You've watched them all", "Every film in \(series.name) is already in Watched.")
                    return
                }
                let name = series.name.replacingOccurrences(of: " Collection", with: "")
                navigationController?.pushViewController(MarathonPlannerViewController(name: name, pieces: pieces), animated: true)
            }
        } else if let season = selectedSeason {
            let episodes = (seasonEpisodes[season] ?? []).filter {
                DateText.isPast($0.airDate) && !watched.contains(EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber))
            }
            guard !episodes.isEmpty else {
                alert("Season \(season) is all watched", "Choose another season first.")
                return
            }
            let pieces = episodes.map {
                Piece(id: detail.id, isEpisode: true, name: detail.name, detail: $0.name, poster: detail.posterPath, backdrop: $0.stillPath ?? detail.backdropPath,
                      minutes: $0.runtime ?? detail.runtime ?? 45, season: $0.seasonNumber, episode: $0.episodeNumber)
            }
            navigationController?.pushViewController(MarathonPlannerViewController(name: "\(detail.name) · Season \(season)", pieces: pieces), animated: true)
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func share() {
        let url = URL(string: "https://www.themoviedb.org/\(item.mediaType.rawValue)/\(item.id)")!
        let sheet = UIActivityViewController(activityItems: [item.name, url], applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    // MARK: Episodes

    /// Marks an episode watched (or not). Marking one past a gap offers to catch up the season.
    private func toggle(_ episode: Episode) {
        guard let detail, DateText.isPast(episode.airDate) else { return }
        let key = EpisodeKey(season: episode.seasonNumber, episode: episode.episodeNumber)
        let runtime = episode.runtime ?? detail.runtime
        if watched.contains(key) {
            Store.shared.setWatched([key], watched: false, show: detail.title, runtime: runtime)
            return
        }
        Haptics.success()
        let earlier = (seasonEpisodes[episode.seasonNumber] ?? [])
            .filter { $0.episodeNumber < episode.episodeNumber && DateText.isPast($0.airDate) }
            .map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) }
            .filter { !watched.contains($0) }
        guard !earlier.isEmpty else {
            Store.shared.setWatched([key], watched: true, show: detail.title, runtime: runtime)
            return
        }
        let sheet = UIAlertController(title: "Catch up the season?", message: "You haven't marked \(earlier.count) earlier episode\(earlier.count == 1 ? "" : "s") in season \(episode.seasonNumber).", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Mark All \(earlier.count + 1) as Watched", style: .default) { _ in
            Store.shared.setWatched(earlier + [key], watched: true, show: detail.title, runtime: runtime)
        })
        sheet.addAction(UIAlertAction(title: "Just This One", style: .default) { _ in
            Store.shared.setWatched([key], watched: true, show: detail.title, runtime: runtime)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let ip = dataSource.indexPath(for: .episode(episode)) { sheet.popoverPresentationController?.sourceView = collectionView.cellForItem(at: ip) }
        present(sheet, animated: true)
    }

    private func seasonMenu() -> UIMenu {
        let seasons = (detail?.mainSeasons ?? []).map { s in
            UIAction(title: "Season \(s.seasonNumber)", subtitle: "\(s.episodeCount) episodes", state: s.seasonNumber == selectedSeason ? .on : .off) { [weak self] _ in
                self?.selectedSeason = s.seasonNumber
                self?.loadSeason(s.seasonNumber)
            }
        }
        let aired = (seasonEpisodes[selectedSeason ?? 0] ?? []).filter { DateText.isPast($0.airDate) }.map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) }
        let all = !aired.isEmpty && aired.allSatisfy(watched.contains)
        let mark = UIAction(title: all ? "Mark Season as Not Watched" : "Mark Season as Watched", image: UIImage(systemName: all ? "circle" : "checkmark.circle")) { [weak self] _ in
            guard let self, let detail else { return }
            Haptics.success()
            Store.shared.setWatched(aired, watched: !all, show: detail.title, runtime: detail.runtime)
        }
        return UIMenu(children: [UIMenu(options: .displayInline, children: seasons), UIMenu(options: .displayInline, children: aired.isEmpty ? [] : [mark])])
    }

    @objc private func storeChanged() {
        if item.mediaType == .tv { watched = Store.shared.watched(show: item.id) }
        refreshHero()
        applySnapshot()
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        if snap.sectionIdentifiers.contains(.episodes) { snap.reloadSections([.episodes]) }
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, let section = self.dataSource?.sectionIdentifier(for: index) else { return nil }
            @MainActor func single(estimated: CGFloat, insets: CGFloat, header: Bool) -> NSCollectionLayoutSection {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimated))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 0, leading: insets, bottom: 28, trailing: insets)
                if header {
                    let h = Shelf.header()
                    h.contentInsets = .init(top: 0, leading: Shelf.margin - insets, bottom: 0, trailing: Shelf.margin - insets)
                    s.boundarySupplementaryItems = [h]
                }
                return s
            }
            switch section {
            case .hero: return single(estimated: 860, insets: 0, header: false)
            case .progress: return single(estimated: 140, insets: Shelf.margin, header: true)
            case .credits: return single(estimated: 70, insets: Shelf.margin, header: false)
            case .rating: return single(estimated: 44, insets: 0, header: true)
            case .episodes:
                let s = Shelf.row(width: Shelf.wide.width, height: 232)
                s.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(50)),
                                                                                            elementKind: SeasonHeader.kind, alignment: .top)]
                return s
            case .providers:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(68))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 0, leading: Shelf.margin, bottom: 32, trailing: Shelf.margin)
                s.boundarySupplementaryItems = [Shelf.header()]
                return s
            case .cast: return Shelf.circles()
            case .more: return Shelf.posters()
            }
        }
    }

    private func configureDataSource() {
        let heroReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(hero) }
        let progressReg = UICollectionView.CellRegistration<WhereYouAreCell, Item> { [unowned self] cell, _, _ in
            let runtime = detail?.runtime ?? 0
            let title = detail?.title ?? item
            cell.configure(position: Int(tracked?.position ?? 0), runtime: runtime, live: live)
            cell.onCommit = { Store.shared.setPosition($0, for: title, runtime: runtime) }
        }
        let creditsReg = UICollectionView.CellRegistration<FactCell, Item> { [unowned self] cell, _, _ in
            let mid = detail?.midCredits ?? false, after = detail?.afterCredits ?? false
            let line = mid && after ? "Scenes during and after the credits. Stay to the very end."
                : after ? "A scene after the credits. Wait for the very end."
                : "A scene during the credits. Nothing at the very end."
            cell.configure(symbol: "popcorn", title: "After-Credits Scene", detail: line)
        }
        let ratingReg = UICollectionView.CellRegistration<RatingCell, Item> { [unowned self] cell, _, _ in
            cell.row.set(Int(tracked?.rating ?? 0))
            cell.row.onChange = { [weak self] value in
                guard let self else { return }
                Store.shared.setRating(value, for: detail?.title ?? item)
            }
        }
        let episodeReg = UICollectionView.CellRegistration<EpisodeLockup, Item> { [unowned self] cell, _, item in
            guard case .episode(let e) = item else { return }
            let key = EpisodeKey(season: e.seasonNumber, episode: e.episodeNumber)
            cell.configure(e, watched: watched.contains(key), aired: DateText.isPast(e.airDate), next: key == nextEpisode, runtime: detail?.runtime)
        }
        let providerReg = UICollectionView.CellRegistration<ProviderRowCell, Item> { [unowned self] cell, indexPath, item in
            guard case .provider(let p) = item else { return }
            let count = dataSource.snapshot().numberOfItems(inSection: .providers)
            cell.configure(p, mine: Prefs.services.contains(p.providerId), first: indexPath.item == 0, last: indexPath.item == count - 1)
        }
        let castReg = UICollectionView.CellRegistration<CircleLockup, Item> { cell, _, item in
            guard case .cast(let c) = item else { return }
            cell.configure(photo: TMDB.imageURL(c.profilePath, .profile), initial: String(c.name.prefix(1)), name: c.name, detail: c.character)
        }
        let posterReg = UICollectionView.CellRegistration<PosterLockup, Item> { cell, _, item in
            if case .title(let t) = item { cell.configure(t) }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .progress: header.configure(live == nil ? "Where You Are" : "Now Showing")
            case .rating: header.configure("Your Rating")
            case .providers: header.configure("How to Watch")
            case .cast: header.configure("Cast & Crew")
            case .more: header.configure("More Like This")
            default: header.configure("")
            }
        }
        let seasonReg = UICollectionView.SupplementaryRegistration<SeasonHeader>(elementKind: SeasonHeader.kind) { [unowned self] header, _, _ in
            let next = nextEpisode
            let states = (seasonEpisodes[selectedSeason ?? 0] ?? []).map { e -> Int in
                let key = EpisodeKey(season: e.seasonNumber, episode: e.episodeNumber)
                return watched.contains(key) ? 2 : key == next ? 1 : 0
            }
            header.configure(season: selectedSeason ?? 1, menu: seasonMenu(), states: states)
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .hero: cv.dequeueConfiguredReusableCell(using: heroReg, for: indexPath, item: item)
            case .progress: cv.dequeueConfiguredReusableCell(using: progressReg, for: indexPath, item: item)
            case .credits: cv.dequeueConfiguredReusableCell(using: creditsReg, for: indexPath, item: item)
            case .rating: cv.dequeueConfiguredReusableCell(using: ratingReg, for: indexPath, item: item)
            case .episode: cv.dequeueConfiguredReusableCell(using: episodeReg, for: indexPath, item: item)
            case .provider: cv.dequeueConfiguredReusableCell(using: providerReg, for: indexPath, item: item)
            case .cast: cv.dequeueConfiguredReusableCell(using: castReg, for: indexPath, item: item)
            case .title: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, kind, indexPath in
            kind == SeasonHeader.kind
                ? cv.dequeueConfiguredReusableSupplementary(using: seasonReg, for: indexPath)
                : cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero])
        snap.appendItems([.hero])
        let status = tracked?.status
        if item.mediaType == .movie, (detail?.runtime ?? 0) > 0, status != .seen || live != nil {
            snap.appendSections([.progress]); snap.appendItems([.progress])
        }
        if let d = detail, d.midCredits || d.afterCredits {
            snap.appendSections([.credits]); snap.appendItems([.credits])
        }
        if let status, status != .watchlist {
            snap.appendSections([.rating]); snap.appendItems([.rating])
        }
        if let n = selectedSeason, let episodes = seasonEpisodes[n], !episodes.isEmpty {
            snap.appendSections([.episodes]); snap.appendItems(episodes.map(Item.episode))
        }
        if let region = detail?.providers[Prefs.region], let flat = region.flatrate, !flat.isEmpty {
            let mine = Prefs.services
            snap.appendSections([.providers])
            snap.appendItems(flat.sorted { mine.contains($0.providerId) && !mine.contains($1.providerId) }.map(Item.provider))
        }
        if let cast = detail?.cast.prefix(12), !cast.isEmpty {
            snap.appendSections([.cast]); snap.appendItems(cast.map(Item.cast))
        }
        if let more = detail?.recommendations.filter({ $0.posterPath != nil }).prefix(12), !more.isEmpty {
            snap.appendSections([.more]); snap.appendItems(more.map(Item.title))
        }
        dataSource.apply(snap, animatingDifferences: detail != nil && !UIAccessibility.isReduceMotionEnabled)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selected = dataSource.itemIdentifier(for: indexPath) else { return }
        switch selected {
        case .episode(let e): toggle(e)
        case .provider:
            if let link = detail?.providers[Prefs.region]?.link, let url = URL(string: link) { UIApplication.shared.open(url) }
        case .title(let t):
            openDetail(t) { [weak self] in
                self?.dataSource.indexPath(for: selected).flatMap { collectionView.cellForItem(at: $0) }
            }
        default: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .episode, .provider, .title: true
        default: false
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .title(let t) = dataSource.itemIdentifier(for: ip) else { return nil }
        return titleMenu(t)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationItem.title = scrollView.contentOffset.y > 520 ? (detail?.name ?? item.name) : nil
    }
}
