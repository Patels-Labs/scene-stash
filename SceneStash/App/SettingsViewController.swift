import StoreKit
import CloudKit
import UIKit

final class SettingsViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Row: Hashable { case pass, icon, alerts, region, services, icloud, replay, version }
    private let sections: [(header: String, rows: [Row], footer: String)] = [
        (Pass.selling ? "All-Access Pass" : "Extras", Pass.selling ? [.pass, .icon, .alerts] : [.icon, .alerts], "Alerts come at six on the evening a new episode lands, and three days before a season premiere. Never more."),
        ("Watching From", [.region, .services], "Your services are highlighted on every title, so you know what's free to watch."),
        ("Sync", [.icloud], "Your library syncs privately through your iCloud account."),
        ("Scene Stash", [.replay, .version], "This product uses the TMDB API but is not endorsed or certified by TMDB. Streaming availability provided by JustWatch."),
    ]
    private var icloudStatus = "Checking…"
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Int, Row>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = Theme.bg
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        configureDataSource()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .passChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .syncChanged, object: nil)
        Task {
            if Store.cloudEnabled {
                let status = try? await CKContainer(identifier: "iCloud.com.heetpatel.scenestash").accountStatus()
                icloudStatus = status == .available ? "On" : "Off — sign in to iCloud to sync"
            } else {
                icloudStatus = "Off in this build"
            }
            reload()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func makeLayout() -> UICollectionViewLayout {
        var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        list.backgroundColor = .clear
        list.headerMode = .supplementary
        list.footerMode = .supplementary
        return UICollectionViewCompositionalLayout.list(using: list)
    }

    private func configureDataSource() {
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { [unowned self] cell, _, row in configure(cell, row) }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [unowned self] view, _, path in
            var config = UIListContentConfiguration.header()
            config.text = sections[path.section].header
            view.contentConfiguration = config
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [unowned self] view, _, path in
            var config = UIListContentConfiguration.footer()
            config.text = sections[path.section].footer
            view.contentConfiguration = config
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, path, row in
            cv.dequeueConfiguredReusableCell(using: cell, for: path, item: row)
        }
        dataSource.supplementaryViewProvider = { cv, kind, path in
            cv.dequeueConfiguredReusableSupplementary(using: kind == UICollectionView.elementKindSectionHeader ? header : footer, for: path)
        }
        var snap = NSDiffableDataSourceSnapshot<Int, Row>()
        for (i, section) in sections.enumerated() {
            snap.appendSections([i])
            snap.appendItems(section.rows, toSection: i)
        }
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func configure(_ cell: UICollectionViewListCell, _ row: Row) {
        var config = UIListContentConfiguration.valueCell()
        cell.accessories = [.disclosureIndicator()]
        switch row {
        case .pass:
            let pass = Pass.shared
            config.text = pass.subscribed ? "All-Access Pass" : "Get the All-Access Pass"
            if pass.subscribed, let ends = pass.periodEnds {
                let days = max(Calendar.current.dateComponents([.day], from: .now, to: ends).day ?? 0, 0) + 1
                let date = ends.formatted(.dateTime.day().month(.abbreviated))
                config.secondaryText = pass.inTrial ? "Trial · \(days) day\(days == 1 ? "" : "s") left" : pass.willRenew ? "Renews \(date)" : "Ends \(date)"
            } else if pass.subscribed {
                config.secondaryText = "Active"
            } else {
                config.secondaryText = pass.trialLength.map { "Try \($0) free" } ?? "\(pass.price)/yr"
            }
            config.image = UIImage(systemName: "star.circle")
        case .icon:
            config.text = "App Icon"
            config.secondaryText = Pass.shared.isUnlocked ? nil : "Pass"
            config.image = UIImage(systemName: Pass.shared.isUnlocked ? "app.badge" : "lock.fill")
        case .alerts:
            config.text = "New Episode Alerts"
            config.image = UIImage(systemName: "bell.badge")
            let toggle = UISwitch()
            toggle.isOn = Alerts.enabled && Pass.shared.isUnlocked
            toggle.accessibilityLabel = "New Episode Alerts"
            toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.toggleAlerts(toggle) }, for: .valueChanged)
            cell.accessories = [.customView(configuration: .init(customView: toggle, placement: .trailing(displayed: .always), maintainsFixedSize: true))]
        case .region:
            config.text = "Region"
            config.secondaryText = Locale.current.localizedString(forRegionCode: Prefs.region) ?? Prefs.region
            config.image = UIImage(systemName: "globe")
        case .services:
            config.text = "Streaming Services"
            config.secondaryText = Prefs.services.isEmpty ? "None" : "\(Prefs.services.count)"
            config.image = UIImage(systemName: "play.tv")
        case .icloud:
            config.text = "iCloud"
            config.secondaryText = icloudStatus
            if icloudStatus == "On", let sync = Store.shared.lastSync {
                config.secondaryText = sync.error.map { "Sync failed: \($0)" }
                    ?? "Synced \(sync.date.formatted(.relative(presentation: .named)))"
            }
            config.image = UIImage(systemName: "icloud")
            cell.accessories = []
        case .replay:
            config.text = "Replay the Intro"
            config.image = UIImage(systemName: "play.circle")
            cell.accessories = []
        case .version:
            let info = Bundle.main.infoDictionary
            config.text = "Version"
            config.secondaryText = "\(info?["CFBundleShortVersionString"] ?? "") (\(info?["CFBundleVersion"] ?? ""))"
            config.image = UIImage(systemName: "info.circle")
            cell.accessories = []
        }
        config.imageProperties.tintColor = Theme.secondary
        cell.contentConfiguration = config
    }

    private func toggleAlerts(_ toggle: UISwitch?) {
        guard let toggle else { return }
        guard Pass.shared.isUnlocked else {
            toggle.setOn(false, animated: true)
            present(PaywallViewController(), animated: true)
            return
        }
        if toggle.isOn {
            Task {
                let on = await Alerts.enable()
                toggle.setOn(on, animated: true)
                if !on {
                    let alert = UIAlertController(title: "Notifications are off", message: "Turn on notifications for Scene Stash in Settings to get new episode alerts.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
        } else {
            Alerts.disable()
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        ![.alerts, .icloud, .version].contains(dataSource.itemIdentifier(for: indexPath))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .pass:
            if Pass.shared.subscribed, let scene = view.window?.windowScene {
                Task { try? await AppStore.showManageSubscriptions(in: scene); await Pass.shared.refresh() }
            } else {
                present(PaywallViewController(), animated: true)
            }
        case .icon: withPass { navigationController?.pushViewController(IconPickerViewController(), animated: true) }
        case .region: navigationController?.pushViewController(RegionViewController(), animated: true)
        case .services:
            let vc = UIViewController()
            vc.title = "Streaming Services"
            vc.view.backgroundColor = Theme.bg
            let picker = ServicesPickerView()
            vc.view.addSubview(picker)
            picker.pin(to: vc.view)
            navigationController?.pushViewController(vc, animated: true)
        case .replay:
            let presenter = presentingViewController
            dismiss(animated: true) {
                let onboarding = OnboardingViewController()
                presenter?.present(onboarding, animated: true)
            }
        default: break
        }
    }
}

final class RegionViewController: UITableViewController, UISearchResultsUpdating {
    private var regions: [Region] = []
    private var filtered: [Region] = []

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Region"
        tableView.backgroundColor = Theme.bg
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        Task {
            do {
                regions = try await TMDB.shared.regions()
                filtered = regions
                tableView.reloadData()
            } catch { showError(error) }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        filtered = text.isEmpty ? regions : regions.filter { $0.englishName.localizedCaseInsensitiveContains(text) }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let region = filtered[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = region.englishName
        cell.contentConfiguration = config
        cell.accessoryType = region.iso31661 == Prefs.region ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Prefs.region = filtered[indexPath.row].iso31661
        Prefs.services = []
        Haptics.tap()
        navigationController?.popViewController(animated: true)
    }
}

/// Grid of streaming service logos for the current region; tapping toggles membership in `Prefs.services`.
final class ServicesPickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private var providers: [Provider] = []
    private let collectionView: UICollectionView
    var limit = 30

    override init(frame: CGRect) {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(104)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
        super.init(frame: frame)
        collectionView.backgroundColor = .clear
        collectionView.register(ProviderCell.self, forCellWithReuseIdentifier: "p")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        addSubview(collectionView)
        collectionView.pin(to: self)
        Task {
            providers = Array(((try? await TMDB.shared.providers(region: Prefs.region)) ?? []).prefix(limit))
            collectionView.reloadData()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { providers.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "p", for: indexPath) as! ProviderCell
        let p = providers[indexPath.item]
        cell.configure(p, mine: Prefs.services.contains(p.providerId), accent: Theme.accent)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        let id = providers[indexPath.item].providerId
        if Prefs.services.contains(id) { Prefs.services.remove(id) } else { Prefs.services.insert(id) }
        Haptics.tap()
        collectionView.reconfigureItems(at: [indexPath])
        return false
    }
}

/// Alternate icons, one of the pass's extras. Holiday icons are listed only around their holiday,
/// and only ever applied when you tap one.
final class IconPickerViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case limited, stock }
    nonisolated private enum Item: Hashable { case limited(Holiday, Date), stock(String?, String) }
    private static let stock: [(name: String?, label: String)] = [
        (nil, "Amber"), ("AppIcon-Red", "Red"), ("AppIcon-Teal", "Teal"), ("AppIcon-Silver", "Silver"), ("AppIcon-Ink", "Ink"),
    ]

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App Icon"
        view.backgroundColor = Theme.bg
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var config = UIListContentConfiguration.subtitleCell()
            let name: String?
            switch item {
            case .limited(let holiday, let ends):
                let last = ends.addingTimeInterval(-1).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                name = holiday.iconName
                config.text = holiday.title
                config.secondaryText = "Until \(last)"
                cell.accessibilityLabel = "\(holiday.title) icon, available until \(last)"
            case .stock(let icon, let label):
                name = icon
                config.text = label
                cell.accessibilityLabel = "\(label) icon"
            }
            config.image = UIImage(named: "Preview-" + (name ?? "AppIcon"))
            config.imageProperties.maximumSize = CGSize(width: 60, height: 60)
            config.imageProperties.reservedLayoutSize = CGSize(width: 60, height: 60)
            config.imageProperties.cornerRadius = 13
            cell.contentConfiguration = config
            let selected = UIApplication.shared.alternateIconName == name
            cell.accessories = selected ? [.checkmark()] : []
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [unowned self] view, _, path in
            var config = UIListContentConfiguration.header()
            config.text = dataSource.sectionIdentifier(for: path.section) == .limited ? "Limited Time" : "Icons"
            view.contentConfiguration = config
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [unowned self] view, _, path in
            var config = UIListContentConfiguration.footer()
            config.text = dataSource.sectionIdentifier(for: path.section) == .limited
                ? "Yours to pick while it's here. Nothing changes unless you tap it."
                : "Choose the icon on your Home Screen."
            view.contentConfiguration = config
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, path, item in
            cv.dequeueConfiguredReusableCell(using: cell, for: path, item: item)
        }
        dataSource.supplementaryViewProvider = { cv, kind, path in
            cv.dequeueConfiguredReusableSupplementary(using: kind == UICollectionView.elementKindSectionHeader ? header : footer, for: path)
        }

        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        let limited = Holiday.available()
        if !limited.isEmpty { snap.appendSections([.limited]); snap.appendItems(limited.map { .limited($0.0, $0.ends) }) }
        snap.appendSections([.stock]); snap.appendItems(Self.stock.map { .stock($0.name, $0.label) })
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func makeLayout() -> UICollectionViewLayout {
        var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        list.backgroundColor = .clear
        list.headerMode = .supplementary
        list.footerMode = .supplementary
        return UICollectionViewCompositionalLayout.list(using: list)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let name: String?
        switch dataSource.itemIdentifier(for: indexPath) {
        case .limited(let holiday, _): name = holiday.iconName
        case .stock(let icon, _): name = icon
        case nil: return
        }
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            guard error == nil else { return }
            DispatchQueue.main.async { [weak self] in
                Haptics.success()
                guard let self else { return }
                var snap = dataSource.snapshot()
                snap.reconfigureItems(snap.itemIdentifiers)
                dataSource.apply(snap, animatingDifferences: false)
            }
        }
    }
}
