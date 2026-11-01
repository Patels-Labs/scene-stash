import UIKit

/// A title as an object: the poster card floats centre stage under its own light, with everything else below.
final class DetailViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case hero, progress, stingers, punchCard, episodes, overview, providers, cast, more }
    nonisolated private enum Item: Hashable {
        case hero, overview, progress, stingers, punchCard
        case provider(Provider), cast(CastMember), episode(Episode), title(Title)
    }

    private let item: Title
    private var detail: TitleDetail?
    private var accent = Theme.accent
    private var selectedSeason: Int?
    private var seasonEpisodes: [Int: [Episode]] = [:]
    private var watched: Set<EpisodeKey> = []
    private var overviewExpanded = false

    private let glow = GlowView()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    // Hero
    private let hero = UIStackView()
    private let poster = TiltCardView()
    private let kicker = UILabel.make(Theme.label(), Theme.secondary)
    private let titleLabel = UILabel.make(Theme.display(50, weight: .black), Theme.text, lines: 0)
    private let meta = UILabel.make(Theme.label(), Theme.tertiary, lines: 0)
    private let billing = UILabel.make(Theme.display(12, weight: .medium, relativeTo: .caption2), Theme.secondary, lines: 0)
    private let tagline = UILabel.make(Theme.text(.callout), Theme.secondary, lines: 0)
    private let nextUp = UILabel.make(Theme.label(.caption1, weight: .bold), Theme.accent, lines: 0)
    private let ticket = TicketButton()
    private let ratingBox = UIStackView()
    private let reel = ReelRatingView()
    private let trailerButton = UIButton(configuration: .glass())
    private let marathonButton = UIButton(configuration: .glass())
    private let buttonRow = UIStackView()

    init(title: Title) {
        item = title
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in self?.share() })

        view.addSubview(glow)
        glow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: view.topAnchor),
            glow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glow.heightAnchor.constraint(equalToConstant: 620),
        ])
        glow.show(TMDB.imageURL(item.posterPath ?? item.backdropPath, .poster))

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        buildHero()
        configureDataSource()
        applyAccent()
        refreshHero()
        applySnapshot()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    // MARK: Loading

    private func load() {
        Task {
            do {
                let detail = try await TMDB.shared.detail(item.id, item.mediaType)
                self.detail = detail
                if item.posterPath == nil {
                    poster.setPoster(detail.posterPath, size: .posterLarge)
                    glow.show(TMDB.imageURL(detail.posterPath, .poster))
                }
                if detail.mediaType == .tv {
                    watched = Store.shared.watched(show: detail.id)
                    let next = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey)
                    selectedSeason = next?.season ?? detail.mainSeasons.first?.seasonNumber
                }
                refreshHero()
                applySnapshot()
                if let season = selectedSeason { loadSeason(season) }
                if let url = TMDB.imageURL(detail.posterPath, .poster), let tint = await ImageLoader.shared.tint(for: url) {
                    accent = tint
                    UIView.animate(withDuration: 0.6) { self.applyAccent() }
                    reconfigureAll()
                }
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

    private func applyAccent() {
        ticket.setTint(accent)
        reel.setAccent(accent)
        nextUp.textColor = accent
        trailerButton.tintColor = .white
        navigationController?.navigationBar.tintColor = Theme.text
    }

    // MARK: Hero

    private func buildHero() {
        poster.cornerRadius = 16
        poster.maxAngle = 0.18
        poster.setPoster(item.posterPath, size: .posterLarge)
        poster.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([poster.widthAnchor.constraint(equalToConstant: 196), poster.heightAnchor.constraint(equalToConstant: 294)])

        [kicker, titleLabel, meta, billing, tagline, nextUp].forEach { $0.textAlignment = .center }
        titleLabel.accessibilityTraits = .header
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6

        ticket.onStash = { [weak self] in self?.stash() }

        let ratingTitle = UILabel.make(Theme.label(), Theme.tertiary)
        ratingTitle.setCaps("Your rating")
        ratingTitle.textAlignment = .center
        ratingBox.axis = .vertical
        ratingBox.spacing = 4
        ratingBox.addArrangedSubview(ratingTitle)
        ratingBox.addArrangedSubview(reel)
        reel.onChange = { [weak self] value in
            guard let self else { return }
            let earned = value >= 9 && !poster.foil
            Store.shared.setRating(value, for: detail?.title ?? item)
            if earned {
                poster.revealFoil()
                Haptics.success()
            }
        }

        trailerButton.configuration?.title = "Watch trailer"
        trailerButton.configuration?.image = UIImage(systemName: "play.fill")
        trailerButton.configuration?.imagePadding = 8
        trailerButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = Theme.text(.subheadline, weight: .semibold); return a
        }
        trailerButton.addAction(UIAction { [weak self] _ in
            if let url = self?.detail?.trailerURL { UIApplication.shared.open(url) }
        }, for: .primaryActionTriggered)

        let posterRow = UIStackView(arrangedSubviews: [poster])
        posterRow.axis = .vertical
        posterRow.alignment = .center
        let titles = UIStackView(arrangedSubviews: [kicker, titleLabel, meta, billing])
        titles.axis = .vertical
        titles.spacing = 6
        titles.setCustomSpacing(14, after: meta)
        marathonButton.configuration?.title = "Plan a marathon"
        marathonButton.configuration?.image = UIImage(systemName: "calendar.badge.clock")
        marathonButton.configuration?.imagePadding = 8
        marathonButton.configuration?.titleTextAttributesTransformer = trailerButton.configuration?.titleTextAttributesTransformer
        marathonButton.addAction(UIAction { [weak self] _ in self?.withPass { self?.planMarathon() } }, for: .primaryActionTriggered)
        buttonRow.addArrangedSubview(trailerButton)
        buttonRow.addArrangedSubview(marathonButton)
        buttonRow.spacing = 10
        let trailerRow = UIStackView(arrangedSubviews: [buttonRow])
        trailerRow.axis = .vertical
        trailerRow.alignment = .center

        [posterRow, titles, tagline, nextUp, ticket, ratingBox, trailerRow].forEach(hero.addArrangedSubview)
        hero.axis = .vertical
        hero.spacing = 18
        hero.setCustomSpacing(30, after: posterRow)
        hero.setCustomSpacing(24, after: nextUp)
        hero.isLayoutMarginsRelativeArrangement = true
        hero.directionalLayoutMargins = .init(top: 0, leading: 22, bottom: 10, trailing: 22)
    }

    private func refreshHero() {
        let d = detail
        var head = [item.mediaType == .movie ? "Film" : "Series"]
        if let year = d?.year ?? item.year { head.append(year) }
        if let runtime = d?.runtime, runtime > 0 { head.append(item.mediaType == .movie ? DateText.runtime(runtime) : "\(runtime) min episodes") }
        kicker.setCaps(head.joined(separator: " · "))
        titleLabel.setDisplay((d?.name ?? item.name).uppercased(), lineHeight: 0.84)

        var bits: [String] = []
        if let genres = d?.genres.prefix(3).map(\.name), !genres.isEmpty { bits.append(genres.joined(separator: " / ")) }
        if let seasons = d?.mainSeasons.count, item.mediaType == .tv, seasons > 0 { bits.append("\(seasons) season\(seasons == 1 ? "" : "s")") }
        if let vote = d?.voteAverage ?? item.voteAverage, vote > 0 { bits.append("TMDB " + vote.formatted(.number.precision(.fractionLength(1)))) }
        meta.setCaps(bits.joined(separator: "  ·  "), kern: 1)
        billing.attributedText = d.map { Self.billingText($0.billing) }
        billing.isHidden = d?.billing.isEmpty ?? true
        tagline.text = d?.tagline.map { "“\($0)”" }
        tagline.isHidden = d?.tagline == nil

        let tracked = Store.shared.tracked(item.id, item.mediaType)
        ticket.configure(status: tracked?.status, menu: statusMenu())
        ratingBox.isHidden = tracked == nil || tracked?.status == .watchlist
        let rating = Int(tracked?.rating ?? 0)
        if !ratingBox.isHidden, reel.value != rating, !reel.isInteracting { reel.set(rating, animated: false) }
        poster.foil = rating >= 9
        trailerButton.isHidden = d?.trailerURL == nil
        marathonButton.isHidden = d.map { item.mediaType == .movie ? $0.collection == nil : $0.mainSeasons.isEmpty } ?? true
        buttonRow.superview?.isHidden = trailerButton.isHidden && marathonButton.isHidden

        if item.mediaType == .tv, let d {
            let remaining = Progress.remaining(seasons: seasonMap, watched: watched, aired: airedKey)
            if let next = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey) {
                nextUp.setCaps(watched.isEmpty ? "Start with \(next.label)" : "Up next \(next.label) · \(remaining) to go", kern: 1.2)
            } else if let upcoming = d.nextEpisodeToAir, let date = upcoming.airDate.flatMap(DateText.pretty) {
                nextUp.setCaps("Caught up · next episode \(date)", kern: 1.2)
            } else {
                nextUp.setCaps(watched.isEmpty ? nil : "All caught up", kern: 1.2)
            }
        } else {
            nextUp.setCaps(nil)
        }
        nextUp.isHidden = nextUp.attributedText == nil
    }

    /// The credits block from the bottom of a poster: roles small, names bright, all one tight run.
    private static func billingText(_ entries: [(role: String?, name: String)]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineHeightMultiple = 1.05
        let out = NSMutableAttributedString()
        for (i, e) in entries.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "  ", attributes: [:])) }
            if let role = e.role { out.append(NSAttributedString(string: role.uppercased() + " ", attributes: [.foregroundColor: Theme.tertiary])) }
            out.append(NSAttributedString(string: e.name.uppercased(), attributes: [.foregroundColor: e.role == nil ? Theme.secondary : Theme.text]))
        }
        out.addAttributes([.paragraphStyle: style, .kern: 0.6], range: NSRange(location: 0, length: out.length))
        return out
    }

    private func statusMenu() -> UIMenu {
        let title = detail?.title ?? item
        let current = Store.shared.tracked(item.id, item.mediaType)?.status
        var actions: [UIMenuElement] = TrackStatus.allCases.map { status in
            UIAction(title: status.label, image: UIImage(systemName: status.symbol), state: current == status ? .on : .off) { [weak self] _ in
                Store.shared.track(title, status: status, runtime: self?.detail?.runtime)
                Haptics.success()
            }
        }
        actions.append(UIAction(title: "Remove from Stash", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            Store.shared.remove(title)
        })
        return UIMenu(children: actions)
    }

    private func stash() {
        let target = stashTabPoint() ?? CGPoint(x: view.bounds.midX, y: view.bounds.maxY)
        ticket.tear(to: target) { [weak self] in
            guard let self else { return }
            Store.shared.track(detail?.title ?? item, status: .watchlist, runtime: detail?.runtime)
        }
    }

    /// Finds the Stash tab's button by its accessibility label to aim the torn stub.
    private func stashTabPoint() -> CGPoint? {
        guard let tabBar = tabBarController?.tabBar, let window = view.window else { return nil }
        func find(_ v: UIView) -> UIView? {
            if v.accessibilityLabel == "Stash" { return v }
            for sub in v.subviews { if let hit = find(sub) { return hit } }
            return nil
        }
        let anchor = find(tabBar) ?? tabBar
        return anchor.convert(CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: window)
    }

    /// A film series becomes a marathon of every released part; a show, the rest of the selected season.
    private func planMarathon() {
        guard let detail else { return }
        Haptics.tap()
        if item.mediaType == .movie, let series = detail.collection {
            marathonButton.isEnabled = false
            Task {
                defer { marathonButton.isEnabled = true }
                let parts = (try? await TMDB.shared.collection(series.id)) ?? []
                var runtimes: [Int: Int] = [:]
                await withTaskGroup(of: (Int, Int?).self) { group in
                    for part in parts { group.addTask { (part.id, try? await TMDB.shared.detail(part.id, .movie).runtime) } }
                    for await (id, runtime) in group { runtimes[id] = runtime }
                }
                // ponytail: unseen parts only; rewatch marathons would need per-marathon progress.
                let pieces = parts.filter { Store.shared.tracked($0.id, .movie)?.status != .seen }
                    .map { Piece(id: $0.id, isEpisode: false, name: $0.name, detail: nil, poster: $0.posterPath, backdrop: $0.backdropPath, minutes: runtimes[$0.id] ?? 120) }
                guard !pieces.isEmpty else {
                    let alert = UIAlertController(title: "You've seen the lot", message: "Every film in \(series.name) is already in your Seen shelf.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
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
                let alert = UIAlertController(title: "Season \(season) is all watched", message: "Pick another season on the punch card.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            let pieces = episodes.map {
                Piece(id: detail.id, isEpisode: true, name: detail.name, detail: $0.name, poster: detail.posterPath, backdrop: $0.stillPath ?? detail.backdropPath,
                      minutes: $0.runtime ?? detail.runtime ?? 45, season: $0.seasonNumber, episode: $0.episodeNumber)
            }
            navigationController?.pushViewController(MarathonPlannerViewController(name: "\(detail.name) · Season \(season)", pieces: pieces), animated: true)
        }
    }

    private func share() {
        let url = URL(string: "https://www.themoviedb.org/\(item.mediaType.rawValue)/\(item.id)")!
        let sheet = UIActivityViewController(activityItems: [item.name, url], applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    // MARK: Episodes

    private func punch(_ episode: Episode) {
        guard let detail else { return }
        let key = EpisodeKey(season: episode.seasonNumber, episode: episode.episodeNumber)
        let runtime = episode.runtime ?? detail.runtime
        if watched.contains(key) {
            Store.shared.setWatched([key], watched: false, show: detail.title, runtime: runtime)
            return
        }
        Haptics.thunk()
        let earlier = (seasonEpisodes[episode.seasonNumber] ?? [])
            .filter { $0.episodeNumber < episode.episodeNumber && DateText.isPast($0.airDate) }
            .map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) }
            .filter { !watched.contains($0) }
        guard !earlier.isEmpty else {
            Store.shared.setWatched([key], watched: true, show: detail.title, runtime: runtime)
            return
        }
        let sheet = UIAlertController(title: "Catch up the season?", message: "You haven't marked \(earlier.count) earlier episode\(earlier.count == 1 ? "" : "s") in season \(episode.seasonNumber).", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Mark all \(earlier.count + 1) watched", style: .default) { _ in
            Store.shared.setWatched(earlier + [key], watched: true, show: detail.title, runtime: runtime)
        })
        sheet.addAction(UIAlertAction(title: "Just this one", style: .default) { _ in
            Store.shared.setWatched([key], watched: true, show: detail.title, runtime: runtime)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.reconfigureAll() })
        if let cell = episodeCell(episode) { sheet.popoverPresentationController?.sourceView = cell.punch }
        present(sheet, animated: true)
    }

    private func punchSeason() {
        guard let detail, let season = selectedSeason, let episodes = seasonEpisodes[season] else { return }
        let aired = episodes.filter { DateText.isPast($0.airDate) }.map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) }
        let all = aired.allSatisfy(watched.contains)
        Haptics.thunk()
        Store.shared.setWatched(aired, watched: !all, show: detail.title, runtime: detail.runtime)
    }

    private func episodeCell(_ episode: Episode) -> EpisodeCell? {
        dataSource.indexPath(for: .episode(episode)).flatMap { collectionView.cellForItem(at: $0) as? EpisodeCell }
    }

    @objc private func storeChanged() {
        let before = watched
        if item.mediaType == .tv { watched = Store.shared.watched(show: item.id) }
        // Animate only the episodes that just got marked.
        for key in watched.subtracting(before) {
            if let episode = seasonEpisodes[key.season]?.first(where: { $0.episodeNumber == key.episode }) {
                episodeCell(episode)?.punch.set(true, animated: true)
            }
        }
        refreshHero()
        applySnapshot()
        reconfigureAll()
    }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, let section = self.dataSource?.sectionIdentifier(for: index) else { return nil }
            let full = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(200))
            func list(spacing: CGFloat) -> NSCollectionLayoutSection {
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: full, subitems: [NSCollectionLayoutItem(layoutSize: full)]))
                s.interGroupSpacing = spacing
                return s
            }
            func row(width: NSCollectionLayoutDimension, height: CGFloat, spacing: CGFloat) -> NSCollectionLayoutSection {
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: width, heightDimension: .absolute(height)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: width, heightDimension: .absolute(height)), subitems: [item])
                let s = NSCollectionLayoutSection(group: group)
                s.orthogonalScrollingBehavior = .continuous
                s.interGroupSpacing = spacing
                return s
            }
            let s: NSCollectionLayoutSection
            switch section {
            case .hero:
                s = list(spacing: 0)
                s.contentInsets = .init(top: 20, leading: 0, bottom: 30, trailing: 0)
                return s
            case .overview, .progress, .stingers, .punchCard, .cast, .episodes: s = list(spacing: 0)
            case .providers: s = row(width: .estimated(150), height: 68, spacing: 10)
            case .more: s = row(width: .absolute(112), height: 168, spacing: 10)
            }
            s.contentInsets = .init(top: 12, leading: 22, bottom: 38, trailing: 22)
            if section == .progress || section == .punchCard || section == .stingers { s.contentInsets = .init(top: 0, leading: 16, bottom: 34, trailing: 16) }
            if ![.overview, .progress, .stingers, .punchCard].contains(section) { s.boundarySupplementaryItems = [Layouts.headerItem()] }
            return s
        }
    }

    private func configureDataSource() {
        let hostReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(hero) }
        let textReg = UICollectionView.CellRegistration<TextCell, Item> { [unowned self] cell, _, _ in
            cell.label.text = detail?.overview.isEmpty == false ? detail?.overview : item.overview
            cell.label.numberOfLines = overviewExpanded ? 0 : 5
            cell.accessibilityHint = overviewExpanded ? nil : "Double tap to read more"
        }
        let providerReg = UICollectionView.CellRegistration<ProviderTicketCell, Item> { [unowned self] cell, _, item in
            if case .provider(let p) = item { cell.configure(p, mine: Prefs.services.contains(p.providerId), accent: accent) }
        }
        let castReg = UICollectionView.CellRegistration<CompanyCell, Item> { cell, _, item in
            if case .cast(let c) = item { cell.configure(c) }
        }
        let progressReg = UICollectionView.CellRegistration<FilmProgressCell, Item> { [unowned self] cell, _, _ in
            let runtime = detail?.runtime ?? 0
            let title = detail?.title ?? item
            cell.configure(position: Int(Store.shared.tracked(item.id, item.mediaType)?.position ?? 0), runtime: runtime, accent: accent)
            cell.onCommit = { Store.shared.setPosition($0, for: title, runtime: runtime) }
            cell.onFinished = {
                Store.shared.track(title, status: .seen, runtime: runtime)
                Haptics.success()
            }
        }
        let stingerReg = UICollectionView.CellRegistration<StingerCell, Item> { [unowned self] cell, _, _ in
            cell.configure(mid: detail?.midCredits ?? false, after: detail?.afterCredits ?? false)
        }
        let punchReg = UICollectionView.CellRegistration<PunchCardCell, Item> { [unowned self] cell, _, _ in
            let card = cell.card
            card.rows = (detail?.mainSeasons ?? []).map { .init(season: $0.seasonNumber, count: $0.episodeCount) }
            card.watched = watched
            card.aired = airedKey
            card.upNext = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey)
            card.selected = selectedSeason
            card.onSelect = { [weak self] n in
                guard let self else { return }
                selectedSeason = n
                reconfigureAll()
                loadSeason(n)
            }
            let remaining = Progress.remaining(seasons: seasonMap, watched: watched, aired: airedKey)
            let aired = seasonMap.reduce(0) { total, season in
                guard let a = airedKey else { return total + season.value }
                return total + (season.key < a.season ? season.value : season.key == a.season ? a.episode : 0)
            }
            cell.configure(remaining: remaining, minutes: remaining * (detail?.runtime ?? 45), punched: watched.count, total: aired, accent: accent)
        }
        let episodeReg = UICollectionView.CellRegistration<EpisodeCell, Item> { [unowned self] cell, _, item in
            guard case .episode(let e) = item else { return }
            let key = EpisodeKey(season: e.seasonNumber, episode: e.episodeNumber)
            let next = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey)
            cell.configure(e, watched: watched.contains(key), aired: DateText.isPast(e.airDate), next: key == next, accent: accent)
            cell.onPunch = { [weak self] in self?.punch(e) }
        }
        let posterReg = UICollectionView.CellRegistration<PosterCell, Item> { cell, _, item in
            if case .title(let t) = item { cell.configure(t) }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .providers: header.configure("Where to watch", caption: "Streaming in \(Prefs.region) · JustWatch")
            case .cast: header.configure("The company", caption: "Starring")
            case .episodes:
                let all = (seasonEpisodes[selectedSeason ?? 0] ?? []).filter { DateText.isPast($0.airDate) }
                    .allSatisfy { watched.contains(EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber)) }
                header.configure("Episodes", caption: "Season \(selectedSeason ?? 1)", accessory: all ? "Unmark all" : "Mark all") { [weak self] in self?.punchSeason() }
                header.accessory.tintColor = accent
            case .more: header.configure("More like this")
            default: header.configure("")
            }
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .hero: cv.dequeueConfiguredReusableCell(using: hostReg, for: indexPath, item: item)
            case .overview: cv.dequeueConfiguredReusableCell(using: textReg, for: indexPath, item: item)
            case .provider: cv.dequeueConfiguredReusableCell(using: providerReg, for: indexPath, item: item)
            case .cast: cv.dequeueConfiguredReusableCell(using: castReg, for: indexPath, item: item)
            case .progress: cv.dequeueConfiguredReusableCell(using: progressReg, for: indexPath, item: item)
            case .punchCard: cv.dequeueConfiguredReusableCell(using: punchReg, for: indexPath, item: item)
            case .stingers: cv.dequeueConfiguredReusableCell(using: stingerReg, for: indexPath, item: item)
            case .episode: cv.dequeueConfiguredReusableCell(using: episodeReg, for: indexPath, item: item)
            case .title: cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero])
        snap.appendItems([.hero])
        let status = Store.shared.tracked(item.id, item.mediaType)?.status
        if item.mediaType == .movie, (detail?.runtime ?? 0) > 0, status != .seen {
            snap.appendSections([.progress]); snap.appendItems([.progress])
        }
        if let d = detail, d.midCredits || d.afterCredits {
            snap.appendSections([.stingers]); snap.appendItems([.stingers])
        }
        if let seasons = detail?.mainSeasons, !seasons.isEmpty {
            snap.appendSections([.punchCard]); snap.appendItems([.punchCard])
            if let n = selectedSeason, let episodes = seasonEpisodes[n] {
                snap.appendSections([.episodes]); snap.appendItems(episodes.map(Item.episode))
            }
        }
        if !(detail?.overview ?? item.overview).isEmpty {
            snap.appendSections([.overview]); snap.appendItems([.overview])
        }
        if let region = detail?.providers[Prefs.region], let flat = region.flatrate, !flat.isEmpty {
            let mine = Prefs.services
            snap.appendSections([.providers])
            snap.appendItems(flat.sorted { mine.contains($0.providerId) && !mine.contains($1.providerId) }.map(Item.provider))
        }
        if let cast = detail?.cast.prefix(8), !cast.isEmpty {
            snap.appendSections([.cast]); snap.appendItems(cast.map(Item.cast))
        }
        if let more = detail?.recommendations.filter({ $0.posterPath != nil }).prefix(12), !more.isEmpty {
            snap.appendSections([.more]); snap.appendItems(more.map(Item.title))
        }
        dataSource.apply(snap, animatingDifferences: detail != nil && !UIAccessibility.isReduceMotionEnabled)
    }

    private func reconfigureAll() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers.filter { $0 != .hero })
        if snap.sectionIdentifiers.contains(.episodes) { snap.reloadSections([.episodes]) }
        dataSource.apply(snap, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let selected = dataSource.itemIdentifier(for: indexPath) else { return }
        switch selected {
        case .overview:
            overviewExpanded.toggle()
            var snap = dataSource.snapshot()
            snap.reconfigureItems([.overview])
            dataSource.apply(snap, animatingDifferences: true)
        case .provider:
            if let link = detail?.providers[Prefs.region]?.link, let url = URL(string: link) { UIApplication.shared.open(url) }
        case .title(let t):
            openDetail(t) { [weak self] in
                self?.dataSource.indexPath(for: selected).flatMap { collectionView.cellForItem(at: $0) }
            }
        default: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .title(let t) = dataSource.itemIdentifier(for: ip) else { return nil }
        return titleMenu(t)
    }

    // The light drifts up slower than the content; pulling down lifts the card toward you.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        glow.transform = CGAffineTransform(translationX: 0, y: -max(y, 0) * 0.4)
        let pull = max(-y, 0)
        poster.transform = CGAffineTransform(scaleX: 1 + pull / 600, y: 1 + pull / 600)
        navigationItem.title = y > 420 ? (detail?.name ?? item.name) : nil
    }
}
