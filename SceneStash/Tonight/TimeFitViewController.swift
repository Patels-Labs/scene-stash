import UIKit

/// "I've Got…": pick how long you have and see what fits, tightest first.
final class TimeFitViewController: UIViewController, UICollectionViewDelegate {
    /// Something you could watch: the rest of a film, a film from the watchlist, or a show's next episodes.
    struct Option {
        enum Kind { case finish, watchlist, episodes(Episode) }
        let title: Title
        let kind: Kind
        /// Minutes per piece, in watching order.
        let pieces: [Int]
    }

    private let options: [Option]
    private let untilLightsUp: Int
    private let onPick: (Option) -> Void
    private let lengths = UISegmentedControl()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: {
        var c = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        c.backgroundColor = .clear
        return c
    }()))
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var fits: [Int: TimeFit.Fit] = [:]

    init(options: [Option], untilLightsUp: Int, onPick: @escaping (Option) -> Void) {
        self.options = options
        self.untilLightsUp = untilLightsUp
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var choices: [(String, Int)] { [("45m", 45), ("1h 30m", 90), ("2h", 120), ("3h", 180), ("All Night", max(untilLightsUp, 180))] }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "I've Got…"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        for (i, c) in choices.enumerated() { lengths.insertSegment(withTitle: c.0, at: i, animated: false) }
        lengths.selectedSegmentIndex = 1
        lengths.addAction(UIAction { [weak self] _ in Haptics.tap(); self?.reload() }, for: .valueChanged)
        list.backgroundColor = .clear
        list.delegate = self
        [lengths, list].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            lengths.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            lengths.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Shelf.margin),
            lengths.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
            list.topAnchor.constraint(equalTo: lengths.bottomAnchor, constant: 4),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let reg = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [unowned self] cell, _, i in
            let o = options[i]
            var c = cell.defaultContentConfiguration()
            c.text = o.title.name
            c.secondaryText = line(o, fits[i])
            c.secondaryTextProperties.color = Theme.secondary
            c.image = UIImage(systemName: o.title.mediaType == .tv ? "tv" : "film")
            c.imageProperties.tintColor = Theme.accent
            cell.contentConfiguration = c
            cell.accessories = [.disclosureIndicator()]
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: list) { cv, ip, i in cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: i) }
        reload()
    }

    private func reload() {
        let minutes = choices[lengths.selectedSegmentIndex].1
        let result = TimeFit.fits(options.map(\.pieces), minutes: minutes)
        fits = Dictionary(uniqueKeysWithValues: result.map { ($0.index, $0) })
        var snap = NSDiffableDataSourceSnapshot<Int, Int>()
        snap.appendSections([0])
        snap.appendItems(result.map(\.index))
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: !UIAccessibility.isReduceMotionEnabled)
        var empty = UIContentUnavailableConfiguration.empty()
        empty.text = "Nothing fits in \(choices[lengths.selectedSegmentIndex].0)"
        empty.secondaryText = options.isEmpty ? "Start a show or add films with a running time to your watchlist." : "Try a longer stretch."
        contentUnavailableConfiguration = result.isEmpty ? empty : nil
    }

    /// "Finish it · 28 min spare", "S2, E4 and E5 · on the dot".
    private func line(_ o: Option, _ fit: TimeFit.Fit?) -> String {
        guard let fit else { return "" }
        let spare = fit.spare <= 2 ? "Finishes on the dot" : "\(DateText.runtime(fit.spare)) spare"
        switch o.kind {
        case .finish: return "Finish it · \(spare)"
        case .watchlist: return "From your watchlist · \(DateText.runtime(fit.used)) · \(spare)"
        case .episodes(let e):
            let first = "S\(e.seasonNumber), E\(e.episodeNumber)"
            return (fit.count == 1 ? first : "\(fit.count) episodes from \(first)") + " · \(spare)"
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let i = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        let option = options[i]
        dismiss(animated: true) { [onPick] in onPick(option) }
    }
}
