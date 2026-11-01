import UIKit

final class DetailViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case hero, overview, providers, cast, seasons, episodes, more }
    nonisolated private enum Item: Hashable {
        case hero, overview
        case provider(Provider), cast(CastMember), season(Int), episode(Episode), title(Title)
    }

    private let item: Title
    private var detail: TitleDetail?
    private var accent = Theme.amber
    private var background = Theme.ink
    private var selectedSeason: Int?
    private var seasonEpisodes: [Int: [Episode]] = [:]
    private var watched: Set<EpisodeKey> = []
    private var overviewExpanded = false

    private let backdrop = UIImageView()
    private let backdropFade = CAGradientLayer()
    private var backdropHeight: NSLayoutConstraint!
    private let baseBackdropHeight: CGFloat = 340
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    // Hero
    private let hero = UIStackView()
    private let poster = UIImageView()
    private let kicker = UILabel()
    private let titleLabel = UILabel()
    private let meta = UILabel()
    private let tagline = UILabel()
    private let ticket = TicketButton()
    private let ratingBox = UIStackView()
    private let reel = ReelRatingView()
    private let nextUp = UILabel()
    private let trailerButton = UIButton(configuration: .glass())

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

        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.layer.addSublayer(backdropFade)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        backdropHeight = backdrop.heightAnchor.constraint(equalToConstant: baseBackdropHeight)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropHeight,
        ])
        backdrop.setImage(TMDB.imageURL(item.backdropPath ?? item.posterPath, .backdrop))

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .never
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        buildHero()
        configureDataSource()
        applyTheme()
        refreshHero()
        applySnapshot()
        load()

        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + 12
        collectionView.verticalScrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropFade.frame = backdrop.bounds
        CATransaction.commit()
    }

    // MARK: Loading

    private func load() {
        Task {
            do {
                let detail = try await TMDB.shared.detail(item.id, item.mediaType)
                self.detail = detail
                if item.backdropPath == nil { backdrop.setImage(TMDB.imageURL(detail.backdropPath, .backdrop)) }
                if detail.mediaType == .tv {
                    watched = Store.shared.watched(show: detail.id)
                    let seasons = detail.mainSeasons.map(\.seasonNumber)
                    let next = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey)
                    selectedSeason = next?.season ?? seasons.first
                }
                refreshHero()
                applySnapshot()
                if let season = selectedSeason { loadSeason(season) }
                if let url = TMDB.imageURL(detail.posterPath, .poster), let tint = await ImageLoader.shared.tint(for: url) {
                    accent = tint
                    UIView.animate(withDuration: 0.6) { self.applyTheme() }
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

    // MARK: Theme

    private func applyTheme() {
        background = Theme.ink.blended(with: accent, amount: 0.14)
        view.backgroundColor = background
        backdropFade.colors = [background.withAlphaComponent(0.1).cgColor, background.withAlphaComponent(0.35).cgColor, background.cgColor]
        backdropFade.locations = [0, 0.55, 1]
        ticket.setTint(accent)
        reel.setAccent(accent)
        kicker.textColor = accent
        nextUp.textColor = accent
        trailerButton.tintColor = accent
        navigationController?.navigationBar.tintColor = Theme.paper
    }

    // MARK: Hero

    private func buildHero() {
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 10
        poster.layer.cornerCurve = .continuous
        poster.backgroundColor = Theme.inkRaised
        poster.setImage(TMDB.imageURL(item.posterPath, .posterLarge))
        poster.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([poster.widthAnchor.constraint(equalToConstant: 104), poster.heightAnchor.constraint(equalToConstant: 156)])

        kicker.font = Theme.mono(.caption1, weight: .bold)
        titleLabel.font = Theme.serif(.largeTitle, weight: .heavy)
        titleLabel.textColor = Theme.paper
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        meta.font = Theme.mono(.caption1, weight: .medium)
        meta.textColor = Theme.muted
        meta.numberOfLines = 0
        [kicker, titleLabel, meta, tagline, nextUp].forEach { $0.adjustsFontForContentSizeCategory = true }

        let titles = UIStackView(arrangedSubviews: [kicker, titleLabel, meta])
        titles.axis = .vertical
        titles.spacing = 4
        let top = UIStackView(arrangedSubviews: [poster, titles])
        top.alignment = .bottom
        top.spacing = 16

        let italic = Theme.serif(.body, weight: .regular).fontDescriptor.withSymbolicTraits(.traitItalic)
        tagline.font = italic.map { UIFont(descriptor: $0, size: 0) } ?? Theme.serif(.body)
        tagline.textColor = Theme.paper.withAlphaComponent(0.7)
        tagline.numberOfLines = 0

        nextUp.font = Theme.mono(.footnote, weight: .bold)

        ticket.onStash = { [weak self] in self?.stash() }

        let ratingTitle = UILabel()
        ratingTitle.text = "YOUR RATING"
        ratingTitle.font = Theme.mono(.caption2, weight: .bold)
        ratingTitle.textColor = Theme.muted
        ratingBox.axis = .vertical
        ratingBox.spacing = 2
        ratingBox.addArrangedSubview(ratingTitle)
        ratingBox.addArrangedSubview(reel)
        reel.onChange = { [weak self] value in
            guard let self else { return }
            Store.shared.setRating(value, for: detail?.title ?? item)
        }

        trailerButton.configuration?.title = "Trailer"
        trailerButton.configuration?.image = UIImage(systemName: "play.fill")
        trailerButton.configuration?.imagePadding = 6
        trailerButton.addAction(UIAction { [weak self] _ in
            if let url = self?.detail?.trailerURL { UIApplication.shared.open(url) }
        }, for: .primaryActionTriggered)
        let actions = UIStackView(arrangedSubviews: [trailerButton, UIView()])

        [top, tagline, nextUp, ticket, ratingBox, actions].forEach(hero.addArrangedSubview)
        hero.axis = .vertical
        hero.spacing = 14
        hero.setCustomSpacing(20, after: top)
        hero.isLayoutMarginsRelativeArrangement = true
        hero.directionalLayoutMargins = .init(top: 0, leading: 20, bottom: 8, trailing: 20)
    }

    private func refreshHero() {
        let d = detail
        kicker.text = [item.mediaType == .movie ? "FILM" : "SERIES", d?.year ?? item.year].compactMap { $0 }.joined(separator: " · ")
        titleLabel.text = d?.name ?? item.name
        var bits: [String] = []
        if let runtime = d?.runtime, runtime > 0 { bits.append(item.mediaType == .movie ? DateText.runtime(runtime) : "\(runtime)m eps") }
        if let seasons = d?.mainSeasons.count, item.mediaType == .tv, seasons > 0 { bits.append("\(seasons) season\(seasons == 1 ? "" : "s")") }
        if let genres = d?.genres.prefix(2).map(\.name), !genres.isEmpty { bits.append(genres.joined(separator: ", ")) }
        if let vote = d?.voteAverage ?? item.voteAverage, vote > 0 { bits.append("★ " + vote.formatted(.number.precision(.fractionLength(1)))) }
        meta.text = bits.joined(separator: "  ·  ")
        tagline.text = d?.tagline
        tagline.isHidden = d?.tagline == nil

        let tracked = Store.shared.tracked(item.id, item.mediaType)
        ticket.configure(status: tracked?.status, menu: statusMenu())
        ratingBox.isHidden = tracked == nil || tracked?.status == .watchlist
        if !ratingBox.isHidden, reel.value != Int(tracked?.rating ?? 0), !reel.isInteracting { reel.set(Int(tracked?.rating ?? 0), animated: false) }
        trailerButton.isHidden = d?.trailerURL == nil

        if item.mediaType == .tv, let d {
            let remaining = Progress.remaining(seasons: seasonMap, watched: watched, aired: airedKey)
            if let next = Progress.nextUp(seasons: seasonMap, watched: watched, aired: airedKey) {
                nextUp.text = watched.isEmpty ? "START WITH \(next.label)" : "UP NEXT  \(next.label)  ·  \(remaining) LEFT"
            } else if let upcoming = d.nextEpisodeToAir, let date = upcoming.airDate.flatMap(DateText.pretty) {
                nextUp.text = "CAUGHT UP · NEXT EPISODE \(date.uppercased())"
            } else {
                nextUp.text = watched.isEmpty ? nil : "ALL CAUGHT UP"
            }
        } else {
            nextUp.text = nil
        }
        nextUp.isHidden = nextUp.text == nil
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
        let sheet = UIAlertController(title: "Catch up the season?", message: "You haven't punched \(earlier.count) earlier episode\(earlier.count == 1 ? "" : "s") in season \(episode.seasonNumber).", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Punch all \(earlier.count + 1)", style: .default) { _ in
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
        // Animate only the episodes that just got punched.
        for key in watched.subtracting(before) {
            if let episode = seasonEpisodes[key.season]?.first(where: { $0.episodeNumber == key.episode }) {
                episodeCell(episode)?.punch.set(true, animated: true)
            }
        }
        refreshHero()
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
                s.contentInsets = .init(top: self.baseBackdropHeight - 110, leading: 0, bottom: 20, trailing: 0)
                return s
            case .overview: s = list(spacing: 0)
            case .providers: s = row(width: .absolute(72), height: 96, spacing: 10)
            case .cast: s = row(width: .absolute(92), height: 150, spacing: 10)
            case .seasons: s = row(width: .estimated(110), height: 34, spacing: 8)
            case .episodes: s = list(spacing: 16)
            case .more: s = row(width: .absolute(110), height: 165, spacing: 12)
            }
            s.contentInsets = .init(top: 10, leading: 20, bottom: 26, trailing: 20)
            if section != .overview && section != .seasons { s.boundarySupplementaryItems = [Layouts.headerItem()] }
            if section == .overview { s.contentInsets.bottom = 26 }
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
        let providerReg = UICollectionView.CellRegistration<ProviderCell, Item> { [unowned self] cell, _, item in
            if case .provider(let p) = item { cell.configure(p, mine: Prefs.services.contains(p.providerId), accent: accent) }
        }
        let castReg = UICollectionView.CellRegistration<CastCell, Item> { cell, _, item in
            if case .cast(let c) = item { cell.configure(c) }
        }
        let chipReg = UICollectionView.CellRegistration<ChipCell, Item> { [unowned self] cell, _, item in
            guard case .season(let n) = item else { return }
            let count = seasonMap[n] ?? 0
            let done = watched.filter { $0.season == n }.count
            cell.accent = accent
            cell.configure("S\(n)", selected: n == selectedSeason, progress: done > 0 ? "\(done)/\(count)" : nil)
        }
        let episodeReg = UICollectionView.CellRegistration<EpisodeCell, Item> { [unowned self] cell, _, item in
            guard case .episode(let e) = item else { return }
            let key = EpisodeKey(season: e.seasonNumber, episode: e.episodeNumber)
            cell.configure(e, watched: watched.contains(key), aired: DateText.isPast(e.airDate), accent: accent)
            cell.onPunch = { [weak self] in self?.punch(e) }
        }
        let posterReg = UICollectionView.CellRegistration<PosterCell, Item> { cell, _, item in
            if case .title(let t) = item { cell.configure(t) }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .providers: header.configure("Where to watch", caption: "Streaming in \(Prefs.region) · via JustWatch")
            case .cast: header.configure("Cast")
            case .episodes:
                let all = (seasonEpisodes[selectedSeason ?? 0] ?? []).filter { DateText.isPast($0.airDate) }
                    .allSatisfy { watched.contains(EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber)) }
                header.configure("Season \(selectedSeason ?? 1)", caption: "Episodes", accessory: all ? "Unpunch all" : "Punch all") { [weak self] in self?.punchSeason() }
                header.accessory.tintColor = accent
            case .more: header.configure("More like this", caption: "If you liked it")
            default: header.configure("")
            }
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .hero: cv.dequeueConfiguredReusableCell(using: hostReg, for: indexPath, item: item)
            case .overview: cv.dequeueConfiguredReusableCell(using: textReg, for: indexPath, item: item)
            case .provider: cv.dequeueConfiguredReusableCell(using: providerReg, for: indexPath, item: item)
            case .cast: cv.dequeueConfiguredReusableCell(using: castReg, for: indexPath, item: item)
            case .season: cv.dequeueConfiguredReusableCell(using: chipReg, for: indexPath, item: item)
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
        if !(detail?.overview ?? item.overview).isEmpty {
            snap.appendSections([.overview]); snap.appendItems([.overview])
        }
        if let region = detail?.providers[Prefs.region], let flat = region.flatrate, !flat.isEmpty {
            let mine = Prefs.services
            snap.appendSections([.providers])
            snap.appendItems(flat.sorted { mine.contains($0.providerId) && !mine.contains($1.providerId) }.map(Item.provider))
        }
        if let cast = detail?.cast.prefix(15), !cast.isEmpty {
            snap.appendSections([.cast]); snap.appendItems(cast.map(Item.cast))
        }
        if let seasons = detail?.mainSeasons, !seasons.isEmpty {
            snap.appendSections([.seasons]); snap.appendItems(seasons.map { .season($0.seasonNumber) })
            if let n = selectedSeason, let episodes = seasonEpisodes[n] {
                snap.appendSections([.episodes]); snap.appendItems(episodes.map(Item.episode))
            }
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
        case .season(let n):
            Haptics.tap()
            selectedSeason = n
            reconfigureAll()
            loadSeason(n)
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

    // Stretchy backdrop: grows when pulled down, drifts up at half speed when scrolled.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        if y < 0 {
            backdropHeight.constant = baseBackdropHeight - y
            backdrop.transform = .identity
        } else {
            backdropHeight.constant = baseBackdropHeight
            backdrop.transform = CGAffineTransform(translationX: 0, y: -y * 0.5)
        }
        navigationItem.title = y > baseBackdropHeight - 40 ? (detail?.name ?? item.name) : nil
    }
}

extension UIColor {
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}
