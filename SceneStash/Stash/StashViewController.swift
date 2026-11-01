import UIKit

final class StashViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case header, cards }
    nonisolated private enum Item: Hashable { case header, card(Title), empty }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let header = StashHeader()
    private var status: TrackStatus { TrackStatus.shelfOrder[header.shelves.selectedIndex] }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stash"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [weak self] _ in
            self?.present(UINavigationController(rootViewController: SettingsViewController()), animated: true)
        })
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Settings"
        header.shelves.addAction(UIAction { [weak self] _ in Haptics.tap(); self?.reload(animated: true) }, for: .valueChanged)

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        // Open on whichever shelf has something on it.
        header.shelves.selectedIndex = TrackStatus.shelfOrder.firstIndex { !Store.shared.all($0).isEmpty } ?? 0
        reload(animated: false)
    }

    @objc private func storeChanged() { reload(animated: true) }

    private func reload(animated: Bool) {
        header.update(stats: Store.shared.stats(), days: Store.shared.watchDays(),
                      counts: TrackStatus.shelfOrder.map { Store.shared.all($0).count })
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.header, .cards])
        snap.appendItems([.header], toSection: .header)
        let items = Store.shared.all(status).map { Item.card($0.title) }
        snap.appendItems(items.isEmpty ? [.empty] : items, toSection: .cards)
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snap.reconfigureItems(items.filter(existing.contains))
        dataSource.apply(snap, animatingDifferences: animated && !UIAccessibility.isReduceMotionEnabled)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            let single = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(300))
            if index == 0 || self?.dataSource?.snapshot().itemIdentifiers(inSection: .cards) == [.empty] {
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: single, subitems: [NSCollectionLayoutItem(layoutSize: single)]))
                s.contentInsets = .init(top: 4, leading: 20, bottom: 26, trailing: 20)
                return s
            }
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.5), heightDimension: .estimated(330)))
            item.contentInsets = .init(top: 0, leading: 9, bottom: 0, trailing: 9)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(330)), subitems: [item, item])
            let s = NSCollectionLayoutSection(group: group)
            s.interGroupSpacing = 26
            s.contentInsets = .init(top: 0, leading: 11, bottom: 40, trailing: 11)
            return s
        }
    }

    private func configureDataSource() {
        let hostReg = UICollectionView.CellRegistration<HostCell, Item> { [unowned self] cell, _, _ in cell.host(header) }
        let cardReg = UICollectionView.CellRegistration<StashCardCell, Item> { cell, _, item in
            if case .card(let t) = item { cell.configure(t) }
        }
        let emptyReg = UICollectionView.CellRegistration<EmptyCell, Item> { [unowned self] cell, _, _ in
            switch status {
            case .watchlist: cell.configure("Nothing saved", "Find something in Discover and tear off a ticket.")
            case .watching: cell.configure("Nothing on the go", "Mark an episode of any show watched to start tracking it.")
            case .seen: cell.configure("No tickets yet", "Mark films and shows as seen and they'll collect here.")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .header: cv.dequeueConfiguredReusableCell(using: hostReg, for: indexPath, item: item)
            case .card: cv.dequeueConfiguredReusableCell(using: cardReg, for: indexPath, item: item)
            case .empty: cv.dequeueConfiguredReusableCell(using: emptyReg, for: indexPath, item: item)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .card = dataSource.itemIdentifier(for: indexPath) { return true }
        return false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .card(let t) = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        openDetail(t) { [weak self] in
            self?.dataSource.indexPath(for: .card(t)).flatMap { (collectionView.cellForItem(at: $0) as? StashCardCell)?.card }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .card(let t) = dataSource.itemIdentifier(for: ip) else { return nil }
        return titleMenu(t)
    }
}

extension TrackStatus {
    static let shelfOrder: [TrackStatus] = [.watching, .watchlist, .seen]
}

// MARK: - Header

/// Big numbers, the year in film as a dot grid, and the shelf switcher.
private final class StashHeader: UIView {
    let shelves = ShelfPicker(titles: TrackStatus.shelfOrder.map(\.label))
    private let numbers = UIStackView()
    private let grid = YearGrid()
    private let gridCaption = UILabel.make(Theme.label(), Theme.tertiary)
    private let streak = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.accent)

    override init(frame: CGRect) {
        super.init(frame: frame)
        numbers.distribution = .fillEqually
        numbers.spacing = 1
        gridCaption.setCaps("Last six months")
        let gridLabels = UIStackView(arrangedSubviews: [gridCaption, UIView(), streak])
        let gridBlock = UIStackView(arrangedSubviews: [gridLabels, grid])
        gridBlock.axis = .vertical
        gridBlock.spacing = 10
        let stack = UIStackView(arrangedSubviews: [numbers, gridBlock, shelves])
        stack.axis = .vertical
        stack.spacing = 26
        stack.setCustomSpacing(34, after: gridBlock)
        addSubview(stack)
        stack.pin(to: self)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(stats: Store.Stats, days: [Date: Int], counts: [Int]) {
        numbers.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hours = stats.minutes / 60
        for (value, caption) in [("\(hours)", "Hours"), ("\(stats.films)", stats.films == 1 ? "Film" : "Films"), ("\(stats.episodes)", "Episodes")] {
            numbers.addArrangedSubview(Self.stat(value, caption))
        }
        grid.days = days
        streak.setCaps(stats.streak > 1 ? "\(stats.streak)-day streak" : nil)
        shelves.counts = counts
    }

    private static func stat(_ value: String, _ caption: String) -> UIView {
        let v = UILabel.make(Theme.display(56, weight: .black))
        v.text = value
        v.adjustsFontSizeToFitWidth = true
        v.minimumScaleFactor = 0.5
        let c = UILabel.make(Theme.label(), Theme.tertiary)
        c.setCaps(caption)
        let stack = UIStackView(arrangedSubviews: [v, c])
        stack.axis = .vertical
        stack.spacing = -2
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(value) \(caption)"
        return stack
    }
}

/// The last 26 weeks as dots, one column per week, lit by how much you watched. Today is ringed.
private final class YearGrid: UIView {
    var days: [Date: Int] = [:] { didSet { setNeedsDisplay(); updateAccessibility() } }
    private let weeks = 30, gap: CGFloat = 3
    private var dot: CGFloat { max((bounds.width - CGFloat(weeks - 1) * gap) / CGFloat(weeks), 4) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        // Height follows width exactly: 7 rows of square dots sized to fit `weeks` columns.
        let n = CGFloat(weeks)
        heightAnchor.constraint(equalTo: widthAnchor, multiplier: 7 / n, constant: 6 * gap - 7 * (n - 1) * gap / n).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today) - 1
        let dot = dot
        for w in 0..<weeks {
            for d in 0..<7 {
                let back = (weeks - 1 - w) * 7 + (weekday - d)
                guard back >= 0, let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
                let cell = CGRect(x: CGFloat(w) * (dot + gap), y: CGFloat(d) * (dot + gap), width: dot, height: dot)
                let count = days[day] ?? 0
                let r = count == 0 ? cell.insetBy(dx: dot * 0.22, dy: dot * 0.22) : cell
                let path = UIBezierPath(ovalIn: r)
                (count == 0 ? UIColor(white: 1, alpha: 0.13) : Theme.accent.withAlphaComponent(min(0.45 + CGFloat(count) * 0.2, 1))).setFill()
                path.fill()
                if back == 0 {
                    UIColor.white.setStroke()
                    let ring = UIBezierPath(ovalIn: cell.insetBy(dx: -1.5, dy: -1.5))
                    ring.lineWidth = 1.2
                    ring.stroke()
                }
            }
        }
    }

    private func updateAccessibility() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -weeks * 7, to: .now) ?? .distantPast
        let active = days.filter { $0.key >= cutoff && $0.value > 0 }.count
        accessibilityLabel = "Watched something on \(active) days in the last six months"
    }
}

/// Three shelves as big compressed words; the selected one is lit.
final class ShelfPicker: UIControl {
    private var buttons: [UIButton] = []
    var selectedIndex = 0 { didSet { restyle() } }
    var counts: [Int] = [] { didSet { restyle() } }
    private let titles: [String]

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.spacing = 18
        stack.alignment = .firstBaseline
        for (i, _) in titles.enumerated() {
            let b = UIButton(type: .custom)
            b.addAction(UIAction { [weak self] _ in
                guard let self, selectedIndex != i else { return }
                selectedIndex = i
                sendActions(for: .valueChanged)
            }, for: .primaryActionTriggered)
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(UIView())
        addSubview(stack)
        stack.pin(to: self)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func restyle() {
        for (i, b) in buttons.enumerated() {
            let selected = i == selectedIndex
            let text = NSMutableAttributedString(string: titles[i].uppercased(), attributes: [
                .font: Theme.display(30, weight: .black), .foregroundColor: selected ? Theme.text : Theme.tertiary,
            ])
            if let count = counts[safe: i], count > 0 {
                text.append(NSAttributedString(string: " \(count)", attributes: [
                    .font: Theme.label(.caption2, weight: .bold), .foregroundColor: selected ? Theme.accent : Theme.tertiary, .baselineOffset: 12,
                ]))
            }
            b.setAttributedTitle(text, for: .normal)
            b.accessibilityLabel = titles[i] + (counts[safe: i].map { ", \($0)" } ?? "")
            b.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }
}

// MARK: - Cells

/// A tracked title as a collectible card with its status written underneath.
final class StashCardCell: UICollectionViewCell {
    let card = TiltCardView()
    private let rating = UILabel.make(Theme.display(22, weight: .black), .black)
    private let name = UILabel.make(Theme.text(.subheadline, weight: .semibold), Theme.text, lines: 2)
    private let meta = UILabel.make(Theme.label(.caption2), Theme.secondary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.maxAngle = 0.1
        rating.textAlignment = .center
        rating.backgroundColor = Theme.accent
        rating.layer.cornerRadius = 8
        rating.layer.cornerCurve = .continuous
        rating.clipsToBounds = true
        let text = UIStackView(arrangedSubviews: [name, meta])
        text.axis = .vertical
        text.spacing = 3
        [card, rating, text].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.heightAnchor.constraint(equalTo: card.widthAnchor, multiplier: 1.5),
            rating.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            rating.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            rating.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            rating.heightAnchor.constraint(equalToConstant: 30),
            text.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: Title) {
        card.setPoster(title.posterPath)
        name.text = title.name
        let tracked = Store.shared.tracked(title.id, title.mediaType)
        let score = Int(tracked?.rating ?? 0)
        rating.text = score > 0 ? "\(score)" : nil
        rating.isHidden = score == 0
        card.foil = score >= 9
        switch tracked?.status ?? .watchlist {
        case .watchlist:
            if let date = title.date, !DateText.isPast(date), let pretty = DateText.pretty(date) {
                meta.setCaps("Out \(pretty)")
                meta.textColor = Theme.accent
            } else {
                meta.setCaps([title.mediaType == .movie ? "Film" : "Series", title.year].compactMap { $0 }.joined(separator: " · "))
                meta.textColor = Theme.secondary
            }
        case .watching:
            let eps = Store.shared.episodes(show: title.id)
            meta.setCaps(eps.map(\.key).max().map { "Last seen \($0.label)" } ?? "Not started")
            meta.textColor = Theme.secondary
        case .seen:
            meta.setCaps(tracked?.watchedAt.map { "Seen " + $0.formatted(.dateTime.month(.abbreviated).year()) })
            meta.textColor = Theme.secondary
        }
        accessibilityLabel = [title.name, meta.accessibilityLabel, score > 0 ? "rated \(score) out of 10" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted, scale: 0.96) } }
}

final class EmptyCell: UICollectionViewCell {
    private let title = UILabel.make(Theme.display(40, weight: .black), Theme.text, lines: 0)
    private let body = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [title, body])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.pin(to: contentView, inset: 0)
        contentView.layoutMargins = .init(top: 30, left: 0, bottom: 30, right: 0)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ title: String, _ body: String) {
        self.title.text = title.uppercased()
        self.body.text = body
        accessibilityLabel = "\(title). \(body)"
    }
}
