import UIKit

/// Every film you've finished as a ticket stub: numbered, dated, in the poster's colour, with your rating
/// on the torn end and a note in your own words. Tens are printed in foil.
final class StubBookViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case intro, month(String) }
    nonisolated private struct Stub: Hashable { let title: Title; let number: Int; let date: Date; let rating: Int; let note: String? }
    nonisolated private enum Item: Hashable { case intro, stub(Stub) }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var count = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        let introReg = UICollectionView.CellRegistration<StubIntroCell, Item> { [unowned self] cell, _, _ in cell.configure(count: count) }
        let stubReg = UICollectionView.CellRegistration<StubCell, Item> { cell, indexPath, item in
            guard case .stub(let stub) = item else { return }
            cell.configure(title: stub.title, number: stub.number, date: stub.date, rating: stub.rating, note: stub.note, tilt: indexPath.item % 2 == 0 ? -0.012 : 0.01)
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            if case .month(let name) = dataSource.sectionIdentifier(for: indexPath.section) { header.configure(name) }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            if case .intro = item { return cv.dequeueConfiguredReusableCell(using: introReg, for: indexPath, item: item) }
            return cv.dequeueConfiguredReusableCell(using: stubReg, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) }
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    @objc private func reload() {
        // Numbered in the order you saw them; shown newest first.
        let seen = Store.shared.all(.seen).filter { $0.mediaType == .movie }
            .sorted { ($0.watchedAt ?? .distantPast) < ($1.watchedAt ?? .distantPast) }
        count = seen.count
        let stubs = seen.enumerated().map { i, t in
            Stub(title: t.title, number: i + 1, date: t.watchedAt ?? t.addedAt ?? .now, rating: Int(t.rating), note: t.note)
        }.reversed()
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.intro]); snap.appendItems([.intro])
        for stub in stubs {
            let month = Section.month(stub.date.formatted(.dateTime.month(.wide).year()))
            if !snap.sectionIdentifiers.contains(month) { snap.appendSections([month]) }
            snap.appendItems([.stub(stub)], toSection: month)
        }
        snap.reconfigureItems([.intro])
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { index, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100))
            let s = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
            if index == 0 {
                s.contentInsets = .init(top: 8, leading: 20, bottom: 18, trailing: 20)
            } else {
                s.interGroupSpacing = 12
                s.contentInsets = .init(top: 10, leading: 16, bottom: 30, trailing: 16)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
            }
            return s
        }
    }

    // Tap a stub to write on it.
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard case .stub(let stub) = dataSource.itemIdentifier(for: indexPath) else { return }
        let alert = UIAlertController(title: stub.title.name, message: "A line about it.", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = stub.note
            field.placeholder = "The sandworm ride. I stood up."
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            Store.shared.setNote(alert?.textFields?.first?.text, for: stub.title)
            Haptics.soft()
        })
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let ip = indexPaths.first, case .stub(let stub) = dataSource.itemIdentifier(for: ip) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Open film", image: UIImage(systemName: "film")) { [weak self] _ in
                self?.openDetail(stub.title) { nil }
            }])
        }
    }
}

private final class StubIntroCell: UICollectionViewCell {
    private let title = UILabel.make(Theme.display(72, weight: .black), Theme.text, lines: 0)
    private let body = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.setDisplay("HISTORY")
        title.accessibilityTraits = .header
        let stack = UIStackView(arrangedSubviews: [title, body])
        stack.axis = .vertical
        stack.spacing = 12
        contentView.addSubview(stack)
        stack.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(count: Int) {
        body.text = count == 0
            ? "Finish a film and it lands here, dated, with your rating. Tap one to add a line."
            : "\(count) film\(count == 1 ? "" : "s") watched. Tap one to add a line."
    }
}

private final class StubCell: UICollectionViewCell {
    private let face = CardView()
    private let wash = CAGradientLayer()
    private let foil = CAGradientLayer()
    private let meta = UILabel.make(Theme.label(.caption2, weight: .bold), UIColor(white: 1, alpha: 0.75))
    private let name = UILabel.make(Theme.display(28, weight: .black))
    private let note = UILabel.make(.italicSystemFont(ofSize: 13), UIColor(white: 1, alpha: 0.78), lines: 2)
    private let rating = UILabel.make(Theme.display(38, weight: .black))
    private let stub = UIView()
    private let perforation = TicketShape.perforation()
    private var shownID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        face.layer.cornerRadius = 14
        face.layer.cornerCurve = .continuous
        face.clipsToBounds = true
        face.backgroundColor = Theme.surfaceHigh
        wash.startPoint = CGPoint(x: 0, y: 0.5)
        wash.endPoint = CGPoint(x: 1, y: 0.5)
        face.layer.addSublayer(wash)
        // Holographic stock for the tens.
        foil.colors = [UIColor(red: 1, green: 0.82, blue: 0.48, alpha: 1), Theme.accent, UIColor(red: 1, green: 0.91, blue: 0.72, alpha: 1),
                       UIColor(red: 0.72, green: 0.89, blue: 1, alpha: 1), UIColor(red: 0.97, green: 0.65, blue: 0.85, alpha: 1), Theme.accent].map(\.cgColor)
        foil.startPoint = CGPoint(x: 0, y: 0.2)
        foil.endPoint = CGPoint(x: 1, y: 0.8)
        face.layer.addSublayer(foil)
        face.onLayout = { [weak self] bounds in
            self?.wash.frame = bounds
            self?.foil.frame = bounds
        }
        stub.backgroundColor = UIColor(white: 0, alpha: 0.2)
        perforation.strokeColor = UIColor(white: 0, alpha: 0.4).cgColor
        stub.layer.addSublayer(perforation)
        rating.textAlignment = .center
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.6
        let text = UIStackView(arrangedSubviews: [meta, name, note])
        text.axis = .vertical
        text.spacing = 6
        contentView.addSubview(face)
        [text, stub].forEach { face.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        stub.addSubview(rating)
        face.pin(to: contentView)
        rating.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: face.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: face.bottomAnchor, constant: -12),
            text.leadingAnchor.constraint(equalTo: face.leadingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: stub.leadingAnchor, constant: -12),
            stub.topAnchor.constraint(equalTo: face.topAnchor),
            stub.bottomAnchor.constraint(equalTo: face.bottomAnchor),
            stub.trailingAnchor.constraint(equalTo: face.trailingAnchor),
            stub.widthAnchor.constraint(equalToConstant: 66),
            rating.centerXAnchor.constraint(equalTo: stub.centerXAnchor),
            rating.centerYAnchor.constraint(equalTo: stub.centerYAnchor),
            face.heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Double tap to write a note"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 0, y: stub.bounds.height - 4))
        perforation.path = p.cgPath
    }

    func configure(title: Title, number: Int, date: Date, rating value: Int, note text: String?, tilt: CGFloat) {
        let ten = value >= 10
        foil.isHidden = !ten
        let ink: UIColor = ten ? .black : .white
        [name, rating].forEach { $0.textColor = ink }
        meta.textColor = ink.withAlphaComponent(0.7)
        note.textColor = ink.withAlphaComponent(0.78)
        meta.setCaps("No. \(String(format: "%04d", number)) · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), kern: 1.2)
        name.text = title.name.uppercased()
        note.text = text.map { "“\($0)”" } ?? "Add a note"
        rating.text = value > 0 ? "\(value)" : "—"
        contentView.transform = CGAffineTransform(rotationAngle: tilt)
        applyWash(Theme.surfaceHigh)
        shownID = title.id
        let id = title.id
        if let url = TMDB.imageURL(title.posterPath, .poster) {
            Task { [weak self] in
                guard let tint = await ImageLoader.shared.tint(for: url), let self, shownID == id else { return }
                applyWash(tint)
            }
        }
        accessibilityLabel = "Film \(number), \(title.name), watched \(date.formatted(date: .long, time: .omitted))" + (value > 0 ? ", rated \(value)" : "") + (text.map { ", note: \($0)" } ?? "")
    }

    private func applyWash(_ tint: UIColor) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        wash.colors = [UIColor(hue: h, saturation: s, brightness: 0.2, alpha: 1), UIColor(hue: h, saturation: s * 0.9, brightness: 0.48, alpha: 1)].map(\.cgColor)
    }

    override var isHighlighted: Bool { didSet { Spring.press(face, isHighlighted, scale: 0.97) } }
}
