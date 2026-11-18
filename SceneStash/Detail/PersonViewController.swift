import UIKit

/// Someone from a cast: their photo, who they are, and shelves of what they're known for and everything else.
final class PersonViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case hero, known, films, shows }
    /// One case per shelf, so a title that's in Known For and Films isn't the same item twice.
    nonisolated private enum Item: Hashable { case hero, known(Person.Credit), film(Person.Credit), show(Person.Credit) }

    private let id: Int
    private let name: String
    private var person: Person?
    private let hero = HeroView()
    private let bio = UILabel.make(Theme.text(.subheadline), UIColor(white: 1, alpha: 0.72), lines: 4)
    private let born = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init(id: Int, name: String, photo: String?) {
        self.id = id
        self.name = name
        super.init(nibName: nil, bundle: nil)
        hero.show(Title(id: id, mediaType: .person, name: name, posterPath: photo), poster: photo, meta: nil, size: .portrait)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        collectionView.backgroundColor = .clear
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = 100
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        bio.isUserInteractionEnabled = true
        bio.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleBio)))
        bio.accessibilityHint = "Double tap to read more"
        [bio, born].forEach {
            $0.isHidden = true
            hero.content.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: hero.content.widthAnchor).isActive = true
        }
        hero.content.setCustomSpacing(8, after: bio)

        let heroReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(hero) }
        let posterReg = UICollectionView.CellRegistration<PosterLockup, Item> { cell, _, item in
            guard let c = Self.credit(item) else { return }
            cell.configure(c.title, caption: c.role, detail: c.title.year)
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, ip in
            switch dataSource.sectionIdentifier(for: ip.section) {
            case .known: header.configure("Known For")
            case .films: header.configure("Films")
            case .shows: header.configure("TV Shows")
            default: header.configure("")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, item in
            item == .hero ? cv.dequeueConfiguredReusableCell(using: heroReg, for: ip, item: item) : cv.dequeueConfiguredReusableCell(using: posterReg, for: ip, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: ip) }
        applySnapshot()
        load()
    }

    private func load() {
        Task {
            do {
                person = try await TMDB.shared.person(id)
                render()
                applySnapshot()
            } catch {
                showError(error)
            }
        }
    }

    private func render() {
        guard let p = person else { return }
        var life: String?
        if let birth = p.birthday.flatMap(DateText.date) {
            let end = p.deathday.flatMap(DateText.date)
            let age = Calendar.current.dateComponents([.year], from: birth, to: end ?? .now).year ?? 0
            let from = birth.formatted(.dateTime.month(.abbreviated).day().year())
            life = end.map { "\(from) – \($0.formatted(.dateTime.month(.abbreviated).day().year())) (aged \(age))" } ?? "Born \(from) (age \(age))"
        }
        let meta = [p.knownForDepartment, life].compactMap { $0 }
        hero.meta.text = meta.joined(separator: " · ")
        hero.meta.isHidden = meta.isEmpty
        bio.text = p.biography
        bio.isHidden = p.biography == nil
        born.text = p.placeOfBirth.map { "Born in \($0)" }
        born.isHidden = p.placeOfBirth == nil
    }

    @objc private func toggleBio() {
        bio.numberOfLines = bio.numberOfLines == 0 ? 4 : 0
        bio.accessibilityHint = bio.numberOfLines == 0 ? nil : "Double tap to read more"
        var snap = dataSource.snapshot()
        snap.reconfigureItems([.hero])
        dataSource.apply(snap, animatingDifferences: !UIAccessibility.isReduceMotionEnabled)
    }

    private func applySnapshot() {
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero])
        snap.appendItems([.hero])
        let credits = person?.credits ?? []
        // TMDB lists a title once per role or job; the first (acting comes first) stands for it.
        func unique(_ list: [Person.Credit]) -> [Person.Credit] {
            var seen = Set<String>()
            return list.filter { seen.insert("\($0.title.mediaType.rawValue)/\($0.title.id)").inserted }
        }
        let known = unique(credits.filter { $0.title.posterPath != nil }.sorted { $0.votes > $1.votes }).prefix(12)
        // Newest first, upcoming ones included; undated ones go last.
        func newest(_ type: MediaType) -> [Person.Credit] {
            unique(credits.filter { $0.title.mediaType == type }).sorted { ($0.title.date ?? "") > ($1.title.date ?? "") }
        }
        for (section, items) in [(Section.known, known.map(Item.known)), (.films, newest(.movie).map(Item.film)), (.shows, newest(.tv).map(Item.show))] where !items.isEmpty {
            snap.appendSections([section])
            snap.appendItems(items)
        }
        dataSource.apply(snap, animatingDifferences: person != nil && !UIAccessibility.isReduceMotionEnabled)
    }

    private static func credit(_ item: Item) -> Person.Credit? {
        switch item {
        case .known(let c), .film(let c), .show(let c): c
        case .hero: nil
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { index, _ in
            guard index > 0 else {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(860))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets.bottom = 28
                return s
            }
            return Shelf.posters(captions: 2)
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { indexPath.section > 0 }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), let c = Self.credit(item) else { return }
        Haptics.tap()
        openDetail(c.title) { [weak self] in self?.dataSource.indexPath(for: item).flatMap { collectionView.cellForItem(at: $0) } }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, let item = dataSource.itemIdentifier(for: ip), let c = Self.credit(item) else { return nil }
        return titleMenu(c.title)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationItem.title = scrollView.contentOffset.y > 520 ? name : nil
    }
}
