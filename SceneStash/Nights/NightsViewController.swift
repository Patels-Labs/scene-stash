import CoreData
import UIKit

/// Movie Nights: the next night out as a big poster card, the rest coming up, and past nights with everyone's ratings.
final class NightsViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case next, coming, past, empty }
    /// Separate cases per section: when a night finishes it moves from a wide card to a poster, and reconfiguring
    /// one identifier across cell types crashes.
    nonisolated private enum Item: Hashable { case next(NSManagedObjectID), coming(NSManagedObjectID), past(NSManagedObjectID), empty }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var clock: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        title = "Movie Nights"
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Plan a Night", image: UIImage(systemName: "plus"), primaryAction: UIAction { [weak self] _ in self?.plan() })
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Store.shared.updateFromNights()
        reload()
        // Stages change with the clock, not just with edits.
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in Store.shared.updateFromNights(); self?.reload() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clock?.invalidate()
    }

    /// Off screen it waits: viewWillAppear reloads, and each reload looks up every night's share.
    @objc private func storeChanged() { if view.window != nil { reload() } }

    private func reload() {
        let nights = Store.shared.nights()
        let upcoming = nights.filter { $0.status() != .creditsRolled }
        let past = nights.filter { $0.status() == .creditsRolled }.reversed()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if let first = upcoming.first {
            snapshot.appendSections([.next]); snapshot.appendItems([.next(first.objectID)])
        } else {
            snapshot.appendSections([.empty]); snapshot.appendItems([.empty])
        }
        if upcoming.count > 1 {
            snapshot.appendSections([.coming]); snapshot.appendItems(upcoming.dropFirst().map { .coming($0.objectID) })
        }
        if !past.isEmpty {
            snapshot.appendSections([.past]); snapshot.appendItems(past.map { .past($0.objectID) })
        }
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { Set(dataSource.snapshot().itemIdentifiers).contains($0) })
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }

    private func plan() {
        let picker = NightFilmPickerViewController { [weak self] night in self?.open(night) }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func open(_ night: MovieNight) {
        navigationController?.pushViewController(NightViewController(night: night), animated: true)
    }

    private func night(_ id: NSManagedObjectID) -> MovieNight? {
        try? Store.shared.context.existingObject(with: id) as? MovieNight
    }

    // MARK: Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, env in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .coming: return Shelf.wides(captions: 2)
            case .past: return Shelf.posters(captions: 2)
            case .next:
                let width = env.container.effectiveContentSize.width - Shelf.margin * 2
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(min(width * 1.15, 480)))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 8, leading: Shelf.margin, bottom: 32, trailing: Shelf.margin)
                return s
            case .empty, nil:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 8, leading: Shelf.margin, bottom: 32, trailing: Shelf.margin)
                return s
            }
        }
    }

    private func configureDataSource() {
        let nextReg = UICollectionView.CellRegistration<NightFeatureCell, NSManagedObjectID> { [weak self] cell, _, id in
            if let night = self?.night(id) { cell.configure(night) }
        }
        let comingReg = UICollectionView.CellRegistration<WideLockup, NSManagedObjectID> { [weak self] cell, _, id in
            guard let night = self?.night(id) else { return }
            let when = (night.showtime ?? .now).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            let stage = night.status()
            let who = night.booked ? night.bookedBy.map { "\(stage.label) by \($0)" } : nil
            cell.configure(.init(backdrop: TMDB.imageURL(night.backdropPath ?? night.posterPath, .backdrop), title: night.name ?? "", badge: stage.label,
                                 caption: when, detail: who ?? night.cinema ?? "Cinema not picked yet"))
        }
        let pastReg = UICollectionView.CellRegistration<PosterLockup, NSManagedObjectID> { [weak self] cell, _, id in
            guard let night = self?.night(id) else { return }
            let ratings = (night.notes ?? []).map { Int($0.rating) }.filter { $0 > 0 }
            let mine = Store.shared.myNote(on: night).map { Int($0.rating) } ?? 0
            let group = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
            let line = [mine > 0 ? "You: \(mine)" : nil, group.map { "Group: " + $0.formatted(.number.precision(.fractionLength(0...1))) }].compactMap { $0 }.joined(separator: " · ")
            cell.configure(night.title, caption: (night.showtime ?? .now).formatted(.dateTime.day().month(.abbreviated)), detail: line.isEmpty ? nil : line, tint: Theme.accent)
        }
        let emptyReg = UICollectionView.CellRegistration<EmptyCell, Item> { cell, _, _ in
            cell.configure("Nothing booked", "Plan a night out, invite your friends, and keep the cinema, screen and seats in one place.")
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .empty: cv.dequeueConfiguredReusableCell(using: emptyReg, for: indexPath, item: item)
            case .next(let id): cv.dequeueConfiguredReusableCell(using: nextReg, for: indexPath, item: id)
            case .coming(let id): cv.dequeueConfiguredReusableCell(using: comingReg, for: indexPath, item: id)
            case .past(let id): cv.dequeueConfiguredReusableCell(using: pastReg, for: indexPath, item: id)
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [weak self] header, _, indexPath in
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .past: header.configure("Past Nights")
            default: header.configure("Coming Up")
            }
        }
        dataSource.supplementaryViewProvider = { cv, kind, indexPath in
            kind == ShelfHeader.kind ? cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) : nil
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .empty
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .next(let id), .coming(let id), .past(let id): if let night = night(id) { Haptics.tap(); open(night) }
        default: break
        }
    }
}

/// The next night out, big: the film's poster with its status, when and where, and who's going.
final class NightFeatureCell: UICollectionViewCell {
    private let art = ArtView(radius: 18)
    private let shade = CAGradientLayer()
    private let badge = GlassLabel()
    private let name = UILabel.make(Theme.text(.largeTitle, weight: .heavy), Theme.text, lines: 2)
    private let logo = UIImageView()
    private var artTask: Task<Void, Never>?
    private let when = UILabel.make(Theme.text(.subheadline), UIColor(white: 1, alpha: 0.85), lines: 2)
    private let place = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 2)
    private let crew = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(art)
        art.pin(to: contentView)
        // Dark enough at the bottom that the words never sit on busy art.
        shade.colors = [UIColor(white: 0, alpha: 0.25), UIColor.clear, UIColor(white: 0, alpha: 0.75), UIColor(white: 0, alpha: 0.95)].map(\.cgColor)
        shade.locations = [0, 0.2, 0.62, 1]
        art.layer.addSublayer(shade)
        [name, when, place].forEach { $0.textAlignment = .center }
        logo.contentMode = .scaleAspectFit
        logo.isHidden = true
        crew.spacing = -9
        let text = UIStackView(arrangedSubviews: [logo, name, when, place, crew])
        text.axis = .vertical
        text.alignment = .center
        text.spacing = 6
        text.setCustomSpacing(12, after: logo)
        text.setCustomSpacing(12, after: place)
        [text, badge].forEach { art.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: art.leadingAnchor, constant: 20),
            text.trailingAnchor.constraint(equalTo: art.trailingAnchor, constant: -20),
            text.bottomAnchor.constraint(equalTo: art.bottomAnchor, constant: -20),
            badge.topAnchor.constraint(equalTo: art.topAnchor, constant: 16),
            badge.leadingAnchor.constraint(equalTo: art.leadingAnchor, constant: 16),
            logo.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            logo.heightAnchor.constraint(equalToConstant: 80),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shade.place(art.bounds)
    }

    func configure(_ night: MovieNight) {
        Task { await HeroView.prepare(night.title) } // so the night's page opens on its finished art
        badge.text = night.status().label
        name.text = night.name
        defer { shownID = night.tmdbID }
        guard night.tmdbID != shownID else { return finish(night) }
        art.show(nil, name: nil)
        name.isHidden = false
        logo.isHidden = true
        // Like the hero: text-free art with the film's logo, so its own title isn't printed twice. The art
        // waits for it rather than showing the regular poster first and swapping.
        artTask?.cancel()
        artTask = Task { [weak self] in
            let artwork = await TMDB.shared.artwork(Int(night.tmdbID), .movie)
            guard !Task.isCancelled, let self else { return }
            if let url = TMDB.imageURL(artwork.poster ?? night.posterPath, .hero), let image = await ImageLoader.shared.image(url), !Task.isCancelled {
                UIView.transition(with: art, duration: 0.25, options: .transitionCrossDissolve) { self.art.image = image }
            }
            guard let url = TMDB.imageURL(artwork.logo, .posterLarge), let image = await ImageLoader.shared.image(url), !Task.isCancelled else { return }
            logo.image = image
            logo.isHidden = false
            name.isHidden = true
        }
        finish(night)
    }

    private var shownID: Int64?

    private func finish(_ night: MovieNight) {
        let showtime = night.showtime ?? .now
        when.text = showtime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · Showtime " + showtime.formatted(date: .omitted, time: .shortened)
            + (night.screen.map { " · Screen \($0)" } ?? "")
        place.text = [night.cinema, night.seats.map { "Seats \($0)" }].compactMap { $0 }.joined(separator: " · ")
        place.isHidden = place.text?.isEmpty ?? true
        crew.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let guests = Store.shared.guests(for: night)
        for (i, guest) in guests.prefix(6).enumerated() { crew.addArrangedSubview(Avatar(guest.initial, index: i, size: 30)) }
        accessibilityLabel = [night.name, night.status().label, when.text, place.text, "\(guests.count) going"].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.98) } }
}

/// A friend's initial in a coloured disc.
final class Avatar: UILabel {
    static let colors: [UIColor] = [Theme.accent, UIColor(red: 0.56, green: 0.83, blue: 0.86, alpha: 1),
                                    UIColor(red: 0.94, green: 0.64, blue: 0.78, alpha: 1), UIColor(red: 0.73, green: 0.88, blue: 0.56, alpha: 1)]

    convenience init(_ initial: String, index: Int, size: CGFloat) {
        self.init()
        text = initial
        font = .systemFont(ofSize: size * 0.42, weight: .heavy)
        textColor = .black
        textAlignment = .center
        backgroundColor = Self.colors[index % Self.colors.count]
        layer.cornerRadius = size / 2
        layer.borderWidth = 2
        layer.borderColor = UIColor.black.cgColor
        clipsToBounds = true
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
    }
}
