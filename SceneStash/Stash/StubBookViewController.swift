import UIKit

/// History: every film you've finished, newest first by month, with your rating and a line in your own words.
final class StubBookViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case intro, month(String) }
    nonisolated private struct Entry: Hashable { let title: Title; let number: Int; let date: Date; let rating: Int; let note: String? }
    nonisolated private enum Item: Hashable { case intro, entry(Entry) }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var count = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.contentInset.bottom = 100
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        let introReg = UICollectionView.CellRegistration<EmptyCell, Item> { [unowned self] cell, _, _ in
            cell.configure(nil, count == 0
                ? "Finish a film and it lands here, dated, with your rating. Tap one to add a line."
                : "\(count) film\(count == 1 ? "" : "s") watched. Tap one to add a line.")
        }
        let entryReg = UICollectionView.CellRegistration<HistoryCell, Item> { cell, _, item in
            guard case .entry(let e) = item else { return }
            cell.configure(title: e.title, number: e.number, date: e.date, rating: e.rating, note: e.note)
        }
        let headerReg = UICollectionView.SupplementaryRegistration<ShelfHeader>(elementKind: ShelfHeader.kind) { [unowned self] header, _, indexPath in
            if case .month(let name) = dataSource.sectionIdentifier(for: indexPath.section) { header.configure(name) }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            if case .intro = item { return cv.dequeueConfiguredReusableCell(using: introReg, for: indexPath, item: item) }
            return cv.dequeueConfiguredReusableCell(using: entryReg, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) }
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    @objc private func reload() {
        // Numbered in the order you watched them; shown newest first.
        let seen = Store.shared.all(.seen).filter { $0.mediaType == .movie }
            .sorted { ($0.watchedAt ?? .distantPast) < ($1.watchedAt ?? .distantPast) }
        count = seen.count
        let entries = seen.enumerated().map { i, t in
            Entry(title: t.title, number: i + 1, date: t.watchedAt ?? t.addedAt ?? .now, rating: Int(t.rating), note: t.note)
        }.reversed()
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.intro]); snap.appendItems([.intro])
        for entry in entries {
            let month = Section.month(entry.date.formatted(.dateTime.month(.wide).year()))
            if !snap.sectionIdentifiers.contains(month) { snap.appendSections([month]) }
            snap.appendItems([.entry(entry)], toSection: month)
        }
        snap.reconfigureItems([.intro])
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { index, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(108))
            let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
            s.interGroupSpacing = 12
            s.contentInsets = .init(top: 0, leading: Shelf.margin, bottom: 32, trailing: Shelf.margin)
            if index > 0 { s.boundarySupplementaryItems = [Shelf.header()] }
            return s
        }
    }

    // Tap a film to write a line about it.
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .entry(let entry) = dataSource.itemIdentifier(for: indexPath) else { return }
        let alert = UIAlertController(title: entry.title.name, message: "A line about it.", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = entry.note
            field.placeholder = "The sandworm ride. I stood up."
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            Store.shared.setNote(alert?.textFields?.first?.text, for: entry.title)
            Haptics.soft()
        })
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .entry(let entry) = dataSource.itemIdentifier(for: ip) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Open Film", image: UIImage(systemName: "film")) { [weak self] _ in
                self?.openDetail(entry.title) { nil }
            }])
        }
    }
}

/// A poster, the film and when you watched it, your line about it, and your rating.
private final class HistoryCell: UICollectionViewCell {
    private let art = ArtView(radius: 10)
    private let name = UILabel.make(Theme.text(.headline, weight: .semibold), Theme.text, lines: 2)
    private let meta = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 2)
    private let rating = UILabel.make(Theme.text(.title2, weight: .bold).monospacedDigits, Theme.accent)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let text = UIStackView(arrangedSubviews: [name, meta, note])
        text.axis = .vertical
        text.spacing = 3
        rating.setContentHuggingPriority(.required, for: .horizontal)
        rating.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [art, text, rating])
        row.alignment = .center
        row.spacing = 14
        contentView.addSubview(row)
        row.pin(to: contentView)
        NSLayoutConstraint.activate([art.widthAnchor.constraint(equalToConstant: 72), art.heightAnchor.constraint(equalToConstant: 108)])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Double tap to write a note"
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: Title, number: Int, date: Date, rating value: Int, note text: String?) {
        art.show(TMDB.imageURL(title.posterPath, .poster), name: title.name)
        name.text = title.name
        meta.text = "Film \(number) · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        note.text = text.map { "“\($0)”" } ?? "Add a note"
        rating.text = "\(value)"
        rating.isHidden = value == 0
        accessibilityLabel = "Film \(number), \(title.name), watched \(date.formatted(date: .long, time: .omitted))" + (value > 0 ? ", rated \(value)" : "") + (text.map { ", note: \($0)" } ?? "")
    }

    override var isHighlighted: Bool { didSet { Spring.press(self, isHighlighted) } }
}
