import UIKit

/// Cinema Passport: round stamps for the countries, decades, directors and genres of the films you've watched,
/// and the ones you're close to. Tap a stamp for the films that earned it.
final class PassportViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case stamps, nearly, note }
    nonisolated private enum Item: Hashable { case stamp(Passport.Stamp), nearly, note }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var facts: [Int: FilmFact] = PassportViewController.cached
    private var nearly: [Passport.Stamp] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cinema Passport"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        render()
        load()
    }

    // MARK: Data

    private static let key = "passportFacts"
    /// Facts don't change once a film is out, so they're kept rather than fetched every visit.
    private static var cached: [Int: FilmFact] {
        get {
            let list = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([FilmFact].self, from: $0) } ?? []
            return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.values)), forKey: key) }
    }

    private var films: [Tracked] { Store.shared.all(.seen).filter { $0.mediaType == .movie } }

    /// Looks up films that aren't in the cache yet, a few at a time so TMDB isn't flooded.
    private func load() {
        let missing = films.map { Int($0.tmdbID) }.filter { facts[$0] == nil }
        guard !missing.isEmpty else { return }
        navigationItem.subtitle = "Checking \(missing.count) film\(missing.count == 1 ? "" : "s")…"
        Task {
            for chunk in stride(from: 0, to: missing.count, by: 8).map({ Array(missing[$0..<min($0 + 8, missing.count)]) }) {
                await withTaskGroup(of: FilmFact?.self) { group in
                    for id in chunk { group.addTask { await TMDB.shared.fact(id) } }
                    for await fact in group { if let fact { facts[fact.id] = fact } }
                }
            }
            Self.cached = facts
            render()
        }
    }

    private func render() {
        let watched = films.compactMap { t in facts[Int(t.tmdbID)].map { ($0, t.viewings.first?.date ?? t.watchedAt ?? t.addedAt ?? .now) } }
        let all = Passport.stamps(watched)
        let earned = all.filter(\.earned).sorted { $0.earnedOn! > $1.earnedOn! }
        nearly = Array(all.filter { !$0.earned && !$0.films.isEmpty }.sorted { $0.progress > $1.progress }.prefix(3))
        let month = earned.filter { Calendar.current.isDate($0.earnedOn!, equalTo: .now, toGranularity: .month) }.count
        navigationItem.subtitle = "\(earned.count) stamp\(earned.count == 1 ? "" : "s")" + (month > 0 ? " · \(month) this month" : "")

        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.stamps])
        snap.appendItems((earned + nearly).map(Item.stamp))
        if !nearly.isEmpty { snap.appendSections([.nearly]); snap.appendItems([.nearly]) }
        snap.appendSections([.note]); snap.appendItems([.note])
        snap.reconfigureItems(snap.itemIdentifiers.filter { Set(dataSource.snapshot().itemIdentifiers).contains($0) })
        dataSource.apply(snap, animatingDifferences: view.window != nil && !UIAccessibility.isReduceMotionEnabled)
    }

    /// "Parasite · Mar", "6 of theirs", "2 to go".
    private func detail(_ s: Passport.Stamp) -> String {
        guard let on = s.earnedOn else { return "\(s.need - s.films.count) to go" }
        switch s.kind {
        case .country: return [facts[s.films[0]]?.name, on.formatted(.dateTime.month(.abbreviated))].compactMap { $0 }.joined(separator: " · ")
        case .director: return "\(s.films.count) of theirs"
        case .decade, .genre: return "\(s.films.count) films"
        case .milestone: return "Reached " + on.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    // MARK: Collection

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .stamps, nil:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / 3), heightDimension: .estimated(150)))
                item.contentInsets = .init(top: 0, leading: 5, bottom: 0, trailing: 5)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(150)), subitems: [item])
                let s = NSCollectionLayoutSection(group: group)
                s.interGroupSpacing = 20
                s.contentInsets = .init(top: 12, leading: Shelf.margin - 5, bottom: 34, trailing: Shelf.margin - 5)
                return s
            case .nearly, .note:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(80))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = .init(top: 0, leading: Shelf.margin, bottom: 16, trailing: Shelf.margin)
                if self?.dataSource?.sectionIdentifier(for: index) == .nearly { s.boundarySupplementaryItems = [Shelf.header()] }
                return s
            }
        }
    }

    private func configureDataSource() {
        let stampReg = UICollectionView.CellRegistration<StampCell, Item> { [unowned self] cell, _, item in
            guard case .stamp(let s) = item else { return }
            cell.configure(s, detail: detail(s))
        }
        let nearlyReg = UICollectionView.CellRegistration<NearlyCell, Item> { [unowned self] cell, _, _ in
            cell.configure(nearly.map { ($0.name, "\($0.films.count) of \($0.need)", $0.progress) })
        }
        let noteReg = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, _ in
            var c = UIListContentConfiguration.footer()
            c.text = "Stamps come from films you've marked watched: one for each country, five for a decade, three by a director, ten in a genre, and milestones along the way."
            c.textProperties.color = Theme.secondary
            cell.contentConfiguration = c
            cell.backgroundConfiguration = .clear()
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { header, _, _ in header.configure("Nearly There") }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, item in
            switch item {
            case .stamp: cv.dequeueConfiguredReusableCell(using: stampReg, for: ip, item: item)
            case .nearly: cv.dequeueConfiguredReusableCell(using: nearlyReg, for: ip, item: item)
            case .note: cv.dequeueConfiguredReusableCell(using: noteReg, for: ip, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: ip) }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .stamp = dataSource.itemIdentifier(for: indexPath) { true } else { false }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .stamp(let s) = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        let titles = s.films.compactMap { Store.shared.tracked($0, .movie)?.title }.reversed()
        navigationController?.pushViewController(LibraryListViewController(heading: s.name, watched: Array(titles)), animated: true)
    }
}

/// A stamp: a coloured disc with its symbol once earned, an outline while it's locked.
private final class StampCell: UICollectionViewCell {
    private let disc = UIView()
    private let icon = UIImageView()
    private let name = UILabel.make(Theme.text(.subheadline, weight: .semibold), Theme.text, lines: 2)
    private let detail = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 2)
    private static let colors: [UIColor] = [
        UIColor(red: 0.94, green: 0.54, blue: 0.48, alpha: 1), UIColor(red: 0.56, green: 0.71, blue: 0.94, alpha: 1),
        UIColor(red: 0.77, green: 0.64, blue: 0.94, alpha: 1), UIColor(red: 0.60, green: 0.85, blue: 0.56, alpha: 1),
        Theme.accent, UIColor(red: 0.56, green: 0.83, blue: 0.86, alpha: 1), UIColor(red: 0.94, green: 0.64, blue: 0.78, alpha: 1),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        disc.layer.cornerRadius = 48
        disc.addSubview(icon)
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = .init(pointSize: 34, weight: .semibold)
        icon.pin(to: disc)
        [name, detail].forEach { $0.textAlignment = .center }
        let stack = UIStackView(arrangedSubviews: [disc, name, detail])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.setCustomSpacing(8, after: disc)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            disc.widthAnchor.constraint(equalToConstant: 96),
            disc.heightAnchor.constraint(equalToConstant: 96),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ s: Passport.Stamp, detail text: String) {
        name.text = s.name
        detail.text = text
        icon.image = UIImage(systemName: Self.symbol(s))
        if s.earned {
            disc.backgroundColor = Self.colors[s.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count]
            disc.layer.borderWidth = 0
            icon.tintColor = .black
        } else {
            disc.backgroundColor = Card.fill
            disc.layer.borderWidth = 2
            disc.layer.borderColor = UIColor(white: 0.47, alpha: 0.36).cgColor
            icon.tintColor = Theme.tertiary
        }
        accessibilityLabel = "\(s.name), \(text)" + (s.earned ? "" : ", not earned yet")
    }

    private static func symbol(_ s: Passport.Stamp) -> String {
        switch s.kind {
        case .country: return "globe"
        case .decade: return "clock"
        case .director: return "megaphone"
        case .milestone: return "star"
        case .genre:
            let genres = ["Horror": "eye", "Comedy": "face.smiling", "Science Fiction": "sparkles", "Animation": "paintbrush", "Romance": "heart",
                          "Documentary": "video", "Music": "music.note", "Action": "bolt", "Thriller": "exclamationmark.triangle", "Drama": "theatermasks",
                          "Western": "sun.dust", "War": "shield", "Family": "house", "Fantasy": "wand.and.stars", "Crime": "magnifyingglass",
                          "Mystery": "questionmark", "History": "building.columns", "Adventure": "map"]
            return genres[s.name] ?? "film"
        }
    }
}

/// Nearly There: each stamp you're closest to, with how far along you are.
private final class NearlyCell: UICollectionViewCell {
    private let rows = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        Card.style(contentView)
        rows.axis = .vertical
        contentView.addSubview(rows)
        rows.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ items: [(name: String, count: String, progress: Double)]) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            if i > 0 {
                let rule = UIView()
                rule.backgroundColor = Card.rule
                rule.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                rows.addArrangedSubview(rule)
            }
            let name = UILabel.make(Theme.text(.body))
            name.text = item.name
            let count = UILabel.make(Theme.text(.footnote).monospacedDigits, Theme.secondary)
            count.text = item.count
            count.setContentHuggingPriority(.required, for: .horizontal)
            let top = UIStackView(arrangedSubviews: [name, count])
            top.alignment = .firstBaseline
            let bar = UIProgressView(progressViewStyle: .bar)
            bar.progress = Float(item.progress)
            bar.progressTintColor = Theme.accent
            bar.trackTintColor = UIColor(white: 0.47, alpha: 0.36)
            bar.layer.cornerRadius = 2
            bar.clipsToBounds = true
            bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
            let row = UIStackView(arrangedSubviews: [top, bar])
            row.axis = .vertical
            row.spacing = 10
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
            row.isAccessibilityElement = true
            row.accessibilityLabel = "\(item.name), \(item.count)"
            rows.addArrangedSubview(row)
        }
    }
}
