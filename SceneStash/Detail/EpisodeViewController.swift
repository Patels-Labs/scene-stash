import UIKit

/// One episode, laid out like a film page: its still, the buttons, where you are, who's in it and what's either side.
final class EpisodeViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case head, progress, guests, around }
    nonisolated private enum Item: Hashable { case head, progress, guest(CastMember), episode(Episode) }

    private let show: Title
    private var episode: Episode
    private var detail: TitleDetail?
    private var season: [Episode] = []

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private let head = UIView()
    private let still = ArtView(radius: 0)
    private let caption = UILabel.make(Theme.text(.subheadline, weight: .semibold), Theme.secondary)
    private let name = UILabel.make(Theme.text(.title1, weight: .bold), Theme.text, lines: 3)
    private let meta = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 2)
    private let overview = UILabel.make(Theme.text(.body), UIColor(white: 1, alpha: 0.8), lines: 0)
    private let primary = CapsuleButton.primary("Start Watching", image: "play.fill")
    private let mark = CapsuleButton.glass("Mark as Watched", image: "checkmark")

    init(show: Title, episode: Episode) {
        self.show = show
        self.episode = episode
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var key: EpisodeKey { EpisodeKey(season: episode.seasonNumber, episode: episode.episodeNumber) }
    private var watched: Set<EpisodeKey> { Store.shared.watched(show: show.id) }
    private var aired: Bool { DateText.isPast(episode.airDate) }
    private var runtime: Int { episode.runtime ?? detail?.runtime ?? 0 }
    private var live: WatchSession.State? { WatchSession.shared.state.flatMap { $0.id == show.id && $0.key == key ? $0 : nil } }
    private var position: Int { Int(Store.shared.tracked(show.id, .tv)?.position ?? 0) }
    /// A show keeps one place, in the episode you're up to, so that's the only one that can be started.
    private var startable: Bool { live != nil || (aired && runtime > 0 && detail?.nextUp(watched: watched) == key) }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        collectionView.backgroundColor = .clear
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        buildHead()
        configureDataSource()
        showEpisode()
        applySnapshot()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .watchChanged, object: nil)
    }

    private func load() {
        Task {
            do {
                let detail = try await TMDB.shared.detail(show.id, .tv)
                let season = try await TMDB.shared.season(show: show.id, number: episode.seasonNumber).episodes
                self.detail = detail
                self.season = season
                if let full = season.first(where: { $0.episodeNumber == episode.episodeNumber }) { episode = full }
                showEpisode()
                applySnapshot()
            } catch {
                showError(error)
            }
        }
    }

    private func buildHead() {
        still.backgroundColor = Theme.surface
        name.accessibilityTraits = .header
        primary.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .primaryActionTriggered)
        mark.addAction(UIAction { [weak self] _ in self?.markTapped() }, for: .primaryActionTriggered)
        let text = UIStackView(arrangedSubviews: [caption, name, meta, primary, mark, overview])
        text.axis = .vertical
        text.spacing = 4
        text.setCustomSpacing(16, after: meta)
        text.setCustomSpacing(10, after: primary)
        text.setCustomSpacing(18, after: mark)
        [still, text].forEach { head.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            still.topAnchor.constraint(equalTo: head.topAnchor),
            still.leadingAnchor.constraint(equalTo: head.leadingAnchor),
            still.trailingAnchor.constraint(equalTo: head.trailingAnchor),
            still.heightAnchor.constraint(equalTo: still.widthAnchor, multiplier: 9.0 / 16),
            text.topAnchor.constraint(equalTo: still.bottomAnchor, constant: 16),
            text.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: Shelf.margin),
            text.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -Shelf.margin),
            text.bottomAnchor.constraint(equalTo: head.bottomAnchor),
        ])
    }

    /// Everything that only changes when the episode's details arrive.
    private func showEpisode() {
        still.show(TMDB.imageURL(episode.stillPath ?? show.backdropPath, .backdrop), name: nil)
        caption.text = "Season \(episode.seasonNumber), Episode \(episode.episodeNumber)"
        name.text = episode.name
        overview.text = episode.overview
        overview.isHidden = episode.overview?.isEmpty ?? true
        let date = episode.airDate.flatMap(DateText.pretty).map { aired ? $0 : "Airs \($0)" }
        meta.text = [show.name, date, runtime > 0 ? DateText.runtime(runtime) : nil].compactMap { $0 }.joined(separator: " · ")
        refreshButtons()
    }

    private func refreshButtons() {
        if let live {
            primary.configuration?.title = live.pausedAt == nil ? "Pause" : "Resume"
            primary.configuration?.image = UIImage(systemName: live.pausedAt == nil ? "pause.fill" : "play.fill")
        } else {
            primary.configuration?.title = position > 0 ? "Resume" : "Start Watching"
            primary.configuration?.image = UIImage(systemName: "play.fill")
        }
        primary.isHidden = !startable
        let seen = watched.contains(key)
        mark.configuration?.title = seen ? "Mark as Not Watched" : "Mark as Watched"
        mark.configuration?.image = UIImage(systemName: seen ? "minus" : "checkmark")
        mark.isHidden = detail == nil || !aired
    }

    private func primaryTapped() {
        if let live {
            Task { live.pausedAt == nil ? await WatchSession.shared.pause() : await WatchSession.shared.resume() }
            return
        }
        guard startable else { return }
        Haptics.tap()
        let title = detail?.title ?? show, runtime = runtime, from = position, key = key
        withPass { Task { await WatchSession.shared.start(title, runtime: runtime, from: from, stinger: false, episode: key) } }
    }

    private func markTapped() {
        guard let detail else { return }
        toggleWatched(episode, season: season, show: detail, from: mark)
    }

    @objc private func storeChanged() {
        refreshButtons()
        applySnapshot()
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
        if let index = snap.indexOfSection(.progress),
           let header = collectionView.supplementaryView(forElementKind: ShelfHeader.kind, at: IndexPath(item: 0, section: index)) as? ShelfHeader {
            header.configure(progressHeading)
        }
    }

    private var progressHeading: String { live == nil ? "Where You Are" : "Now Showing" }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self, let section = self.dataSource?.sectionIdentifier(for: index) else { return nil }
            @MainActor func single(estimated: CGFloat, insets: CGFloat) -> NSCollectionLayoutSection {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimated))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 0, leading: insets, bottom: 28, trailing: insets)
                return s
            }
            switch section {
            case .head: return single(estimated: 520, insets: 0)
            case .progress:
                let s = single(estimated: 140, insets: Shelf.margin)
                s.boundarySupplementaryItems = [Shelf.header()]
                return s
            case .guests: return Shelf.circles()
            case .around: return Shelf.row(width: Shelf.wide.width, height: 232)
            }
        }
    }

    private func configureDataSource() {
        let headReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(head) }
        let progressReg = UICollectionView.CellRegistration<WhereYouAreCell, Item> { [unowned self] cell, _, _ in
            let title = detail?.title ?? show, runtime = runtime
            cell.configure(position: position, runtime: runtime, live: live)
            cell.onCommit = { Store.shared.setPosition($0, for: title, runtime: runtime) }
        }
        let guestReg = UICollectionView.CellRegistration<CircleLockup, Item> { cell, _, item in
            guard case .guest(let c) = item else { return }
            cell.configure(photo: TMDB.imageURL(c.profilePath, .profile), initial: String(c.name.prefix(1)), name: c.name, detail: c.character)
        }
        let episodeReg = UICollectionView.CellRegistration<EpisodeLockup, Item> { [unowned self] cell, _, item in
            guard case .episode(let e) = item else { return }
            let key = EpisodeKey(season: e.seasonNumber, episode: e.episodeNumber)
            cell.configure(e, watched: watched.contains(key), aired: DateText.isPast(e.airDate), next: key == detail?.nextUp(watched: watched), runtime: detail?.runtime)
            cell.onTick = { [weak self, weak cell] in
                guard let self, let detail else { return }
                toggleWatched(e, season: season, show: detail, from: cell)
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .progress: header.configure(progressHeading)
            case .guests: header.configure("Guest Stars")
            case .around: header.configure("More Episodes")
            default: header.configure("")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .head: cv.dequeueConfiguredReusableCell(using: headReg, for: indexPath, item: item)
            case .progress: cv.dequeueConfiguredReusableCell(using: progressReg, for: indexPath, item: item)
            case .guest: cv.dequeueConfiguredReusableCell(using: guestReg, for: indexPath, item: item)
            case .episode: cv.dequeueConfiguredReusableCell(using: episodeReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.head])
        snap.appendItems([.head])
        if startable {
            snap.appendSections([.progress])
            snap.appendItems([.progress])
        }
        // TMDB can bill someone twice, and a repeated item would crash the data source.
        var seen = Set<Int>()
        let guests = (episode.guestStars ?? []).filter { seen.insert($0.id).inserted }
        if !guests.isEmpty {
            snap.appendSections([.guests])
            snap.appendItems(guests.map(Item.guest))
        }
        let around = season.filter { abs($0.episodeNumber - episode.episodeNumber) == 1 }
        if !around.isEmpty {
            snap.appendSections([.around])
            snap.appendItems(around.map(Item.episode))
        }
        dataSource.apply(snap, animatingDifferences: detail != nil && !UIAccessibility.isReduceMotionEnabled)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .episode = dataSource.itemIdentifier(for: indexPath) { true } else { false }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .episode(let e) = dataSource.itemIdentifier(for: indexPath), let navigationController else { return }
        Haptics.tap()
        // Swaps this page rather than stacking on it, so Back always goes to the show.
        var stack = navigationController.viewControllers
        stack[stack.count - 1] = EpisodeViewController(show: show, episode: e)
        navigationController.setViewControllers(stack, animated: true)
    }
}

extension TitleDetail {
    func nextUp(watched: Set<EpisodeKey>) -> EpisodeKey? {
        Progress.nextUp(seasons: Dictionary(uniqueKeysWithValues: mainSeasons.map { ($0.seasonNumber, $0.episodeCount) }), watched: watched,
                        aired: lastEpisodeToAir.map { EpisodeKey(season: $0.seasonNumber, episode: $0.episodeNumber) })
    }
}

extension UIViewController {
    /// Marks an episode watched (or not). Marking one past a gap offers to catch up the season.
    func toggleWatched(_ episode: Episode, season: [Episode], show detail: TitleDetail, from source: UIView?) {
        guard DateText.isPast(episode.airDate) else { return }
        let key = EpisodeKey(season: episode.seasonNumber, episode: episode.episodeNumber)
        let runtime = episode.runtime ?? detail.runtime
        let watched = Store.shared.watched(show: detail.id)
        if WatchSession.shared.state?.id == detail.id, WatchSession.shared.state?.key == key {
            Task { await WatchSession.shared.finish() }
            return
        }
        if watched.contains(key) {
            Store.shared.setWatched([key], watched: false, show: detail.title, runtime: runtime)
            return
        }
        Haptics.success()
        let earlier = season
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
        sheet.popoverPresentationController?.sourceView = source
        present(sheet, animated: true)
    }
}
