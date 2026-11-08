import UIKit

/// Your year so far on one page: the title you watched most, the numbers, and the films. Shareable as an image.
final class YearViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case hero, stats, tens, films }
    nonisolated private enum Item: Hashable {
        case hero, stats, ten(Title), film(Title, String?)

        var title: Title? {
            switch self {
            case .ten(let t), .film(let t, _): t
            case .hero, .stats: nil
            }
        }
    }

    private struct Year {
        var minutes = 0, episodes = 0, bestStreak = 0
        var films: [Tracked] = []
        var tens: [Title] = []
        var topShow: (title: Title, episodes: Int, minutes: Int)?
        var busiestMonth: (String, Int)?
    }

    private let year = Calendar.current.component(.year, from: .now)
    private let hero = HeroView()
    private let grid = UIStackView()
    private let share = CapsuleButton.primary("Share", image: "square.and.arrow.up")
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        collectionView.backgroundColor = .clear
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        collectionView.delegate = self
        // The art runs up under the status bar, like the TV app.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.bottom = 40
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        let close = CapsuleButton.circle("xmark", label: "Close")
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
        ])
        share.addAction(UIAction { [weak self] _ in self?.shareYear() }, for: .primaryActionTriggered)

        let stats = compute()
        buildHero(stats)
        buildGrid(stats)
        configureDataSource()

        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero]); snap.appendItems([.hero])
        if !grid.arrangedSubviews.isEmpty { snap.appendSections([.stats]); snap.appendItems([.stats]) }
        if !stats.tens.isEmpty { snap.appendSections([.tens]); snap.appendItems(stats.tens.map(Item.ten)) }
        if !stats.films.isEmpty {
            snap.appendSections([.films])
            snap.appendItems(stats.films.map { Item.film($0.title, $0.watchedAt?.formatted(.dateTime.month(.abbreviated).day())) })
        }
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func shareYear() {
        // The hero as an image, without the button that made it.
        share.alpha = 0
        let image = UIGraphicsImageRenderer(bounds: hero.bounds).image { _ in
            hero.drawHierarchy(in: hero.bounds, afterScreenUpdates: true)
        }
        share.alpha = 1
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = share
        present(sheet, animated: true)
    }

    // MARK: Stats

    private func compute() -> Year {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        let films = Store.shared.all(.seen).filter { $0.mediaType == .movie && ($0.watchedAt ?? .distantPast) >= start }
            .sorted { ($0.watchedAt ?? .distantPast) > ($1.watchedAt ?? .distantPast) }
        let episodes = Store.shared.episodes().filter { ($0.watchedAt ?? .distantPast) >= start }
        var y = Year()
        y.films = films
        y.episodes = episodes.count
        y.minutes = films.reduce(0) { $0 + Int($1.runtime) } + episodes.reduce(0) { $0 + Int($1.runtime) }
        y.tens = Store.shared.all().filter { $0.rating >= 10 }.map(\.title)
        if let (show, eps) = Dictionary(grouping: episodes, by: \.showID).max(by: { $0.value.count < $1.value.count }),
           let tracked = Store.shared.tracked(Int(show), .tv) {
            y.topShow = (tracked.title, eps.count, eps.reduce(0) { $0 + Int($1.runtime) })
        }
        let dates = films.compactMap(\.watchedAt) + episodes.compactMap(\.watchedAt)
        if let (month, count) = Dictionary(grouping: dates, by: { cal.component(.month, from: $0) }).mapValues(\.count).max(by: { $0.value < $1.value }) {
            y.busiestMonth = (cal.monthSymbols[month - 1], count)
        }
        let days = Set(dates.map { cal.startOfDay(for: $0) }).sorted()
        var run = 0, best = 0, previous: Date?
        for day in days {
            run = previous.flatMap { cal.dateComponents([.day], from: $0, to: day).day } == 1 ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        y.bestStreak = best
        return y
    }

    // MARK: Content

    private func buildHero(_ y: Year) {
        if let lead = y.topShow?.title ?? y.films.first?.title {
            hero.show(lead, meta: (y.topShow == nil ? "Latest film of " : "Most watched of ") + "\(year)")
        } else {
            hero.name.text = "Your \(year)"
            hero.meta.text = "Nothing watched yet this year."
        }
        let hours = y.minutes / 60
        let numbers = UIStackView(arrangedSubviews: [
            stat("\(hours)", hours == 1 ? "Hour" : "Hours", font: Theme.text(.largeTitle, weight: .bold), align: .center),
            stat("\(y.films.count)", y.films.count == 1 ? "Film" : "Films", font: Theme.text(.largeTitle, weight: .bold), align: .center),
            stat("\(y.episodes)", y.episodes == 1 ? "Episode" : "Episodes", font: Theme.text(.largeTitle, weight: .bold), align: .center),
        ])
        numbers.distribution = .fillEqually
        [numbers, share].forEach {
            hero.content.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: hero.content.widthAnchor).isActive = true
        }
        hero.content.setCustomSpacing(18, after: numbers)
    }

    private func buildGrid(_ y: Year) {
        var tiles: [(String, String)] = []
        if let top = y.topShow {
            tiles.append((DateText.runtime(top.minutes), "\(top.episodes) episode\(top.episodes == 1 ? "" : "s") of \(top.title.name)"))
        }
        if !y.tens.isEmpty { tiles.append(("\(y.tens.count)", y.tens.count == 1 ? "Perfect Ten" : "Perfect Tens")) }
        if let (month, count) = y.busiestMonth { tiles.append((month, "Busiest month, \(count) watched")) }
        if y.bestStreak > 0 { tiles.append(("\(y.bestStreak) day\(y.bestStreak == 1 ? "" : "s")", "Longest run")) }

        grid.axis = .vertical
        grid.spacing = Shelf.gap
        for start in stride(from: 0, to: tiles.count, by: 2) {
            var cells: [UIView] = tiles[start..<min(start + 2, tiles.count)].map { value, caption in
                let tile = UIView()
                Card.style(tile)
                let s = stat(value, caption, font: Theme.text(.title1, weight: .bold), align: .natural)
                tile.addSubview(s)
                s.pin(to: tile, inset: 16)
                return tile
            }
            if cells.count == 1 { cells.append(UIView()) }
            let row = UIStackView(arrangedSubviews: cells)
            row.spacing = Shelf.gap
            row.distribution = .fillEqually
            grid.addArrangedSubview(row)
        }
    }

    private func stat(_ value: String, _ caption: String, font: UIFont, align: NSTextAlignment) -> UIStackView {
        let v = UILabel.make(font.monospacedDigits)
        v.text = value
        v.textAlignment = align
        v.adjustsFontSizeToFitWidth = true
        v.minimumScaleFactor = 0.6
        let c = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
        c.text = caption
        c.textAlignment = align
        let s = UIStackView(arrangedSubviews: [v, c])
        s.axis = .vertical
        s.spacing = 2
        s.isAccessibilityElement = true
        s.accessibilityLabel = "\(value) \(caption)"
        return s
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .tens: return Shelf.posters()
            case .films: return Shelf.posters(captions: 1)
            case .hero, .stats, nil:
                let isHero = index == 0
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(isHero ? 620 : 200))
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [.init(layoutSize: size)]))
                s.contentInsets = isHero ? .init(top: 0, leading: 0, bottom: 24, trailing: 0)
                    : .init(top: 0, leading: Shelf.margin, bottom: 32, trailing: Shelf.margin)
                return s
            }
        }
    }

    private func configureDataSource() {
        let hostReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, item in
            cell.host(item == .hero ? hero : grid)
        }
        let posterReg = UICollectionView.CellRegistration<PosterLockup, Item> { cell, _, item in
            switch item {
            case .ten(let t): cell.configure(t)
            case .film(let t, let date): cell.configure(t, detail: date)
            case .hero, .stats: break
            }
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, indexPath in
            header.configure(dataSource.sectionIdentifier(for: indexPath.section) == .tens ? "Perfect Tens" : "Watched in \(year)")
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            if item.title == nil { return cv.dequeueConfiguredReusableCell(using: hostReg, for: indexPath, item: item) }
            return cv.dequeueConfiguredReusableCell(using: posterReg, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath)?.title != nil
    }

    // This page is presented on its own, so a title opens in a sheet over it.
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let title = dataSource.itemIdentifier(for: indexPath)?.title else { return }
        Haptics.tap()
        present(UINavigationController(rootViewController: DetailViewController(title: title)), animated: true)
    }
}
