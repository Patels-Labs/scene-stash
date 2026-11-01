import StoreKit
import CloudKit
import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row { case pass, icon, alerts, region, services, icloud, replay, version }
    private let sections: [(String?, [Row], String?)] = [
        (Pass.selling ? "All-Access Pass" : "Extras", Pass.selling ? [.pass, .icon, .alerts] : [.icon, .alerts], "Alerts come at six on the evening a new episode lands, and three days before a season premiere. Never more."),
        ("Watching from", [.region, .services], "Your services are highlighted on every title, so you know what's free to watch."),
        ("Sync", [.icloud], "Your stash syncs privately through your iCloud account."),
        ("Scene Stash", [.replay, .version], "This product uses the TMDB API but is not endorsed or certified by TMDB. Streaming availability provided by JustWatch."),
    ]
    private var icloudStatus = "Checking…"

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.backgroundColor = Theme.bg
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .passChanged, object: nil)
        Task {
            guard Store.cloudEnabled else { icloudStatus = "Off in this build"; return }
            let status = try? await CKContainer(identifier: "iCloud.com.heetpatel.scenestash").accountStatus()
            icloudStatus = status == .available ? "On" : "Off — sign in to iCloud to sync"
            tableView.reloadData()
        }
        NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .syncChanged, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].2 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = UIListContentConfiguration.valueCell()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        switch sections[indexPath.section].1[indexPath.row] {
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
            config.image = UIImage(systemName: "ticket.fill")
            cell.accessoryType = .disclosureIndicator
        case .icon:
            config.text = "App icon"
            config.secondaryText = Pass.shared.isUnlocked ? nil : "Pass"
            config.image = UIImage(systemName: Pass.shared.isUnlocked ? "app.badge" : "lock.fill")
            cell.accessoryType = .disclosureIndicator
        case .alerts:
            config.text = "Premiere alerts"
            config.image = UIImage(systemName: "bell.badge")
            let toggle = UISwitch()
            toggle.isOn = Alerts.enabled && Pass.shared.isUnlocked
            toggle.onTintColor = Theme.accent
            toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.toggleAlerts(toggle) }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .region:
            config.text = "Region"
            config.secondaryText = Locale.current.localizedString(forRegionCode: Prefs.region) ?? Prefs.region
            config.image = UIImage(systemName: "globe")
            cell.accessoryType = .disclosureIndicator
        case .services:
            config.text = "Streaming services"
            config.secondaryText = Prefs.services.isEmpty ? "None" : "\(Prefs.services.count)"
            config.image = UIImage(systemName: "play.tv")
            cell.accessoryType = .disclosureIndicator
        case .icloud:
            config.text = "iCloud"
            config.secondaryText = icloudStatus
            if icloudStatus == "On", let sync = Store.shared.lastSync {
                config.secondaryText = sync.error.map { "Sync failed: \($0)" }
                    ?? "Synced \(sync.date.formatted(.relative(presentation: .named)))"
            }
            config.image = UIImage(systemName: "icloud")
            cell.selectionStyle = .none
        case .replay:
            config.text = "Replay the intro"
            config.image = UIImage(systemName: "film")
        case .version:
            let info = Bundle.main.infoDictionary
            config.text = "Version"
            config.secondaryText = "\(info?["CFBundleShortVersionString"] ?? "") (\(info?["CFBundleVersion"] ?? ""))"
            config.image = UIImage(systemName: "ticket")
            cell.selectionStyle = .none
        }
        config.imageProperties.tintColor = Theme.accent
        cell.contentConfiguration = config
        return cell
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
                    let alert = UIAlertController(title: "Notifications are off", message: "Turn on notifications for Scene Stash in Settings to get premiere alerts.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
        } else {
            Alerts.disable()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].1[indexPath.row] {
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
            vc.title = "Streaming services"
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
        NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .passChanged, object: nil)
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
                    let alert = UIAlertController(title: "Notifications are off", message: "Turn on notifications for Scene Stash in Settings to get premiere alerts.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
        } else {
            Alerts.disable()
        }
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
        if let cell = collectionView.cellForItem(at: indexPath), !UIAccessibility.isReduceMotionEnabled {
            cell.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.5) { cell.transform = .identity }
        }
        return false
    }
}

/// "Ticket stock": alternate icons, one of the pass's extras. Holiday stock is listed only around its holiday,
/// and only ever applied when you tap it.
final class IconPickerViewController: UIViewController, UICollectionViewDelegate {
    nonisolated private enum Section: Hashable { case hero, limited, stock }
    nonisolated private enum Item: Hashable { case hero, limited(Holiday, Date), stock(String?) }
    private static let stock: [(name: String?, label: String)] = [
        (nil, "Amber"), ("AppIcon-Red", "Red"), ("AppIcon-Teal", "Teal"), ("AppIcon-Silver", "Silver"), ("AppIcon-Ink", "Ink"),
    ]

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App icon"
        view.backgroundColor = Theme.bg
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)

        let heroReg = UICollectionView.CellRegistration<IconHeroCell, Item> { cell, _, _ in
            let current = UIApplication.shared.alternateIconName
            cell.configure(image: UIImage(named: "Preview-" + (current ?? "AppIcon")), name: Self.label(for: current))
        }
        let limitedReg = UICollectionView.CellRegistration<LimitedIconCell, Item> { cell, _, item in
            guard case .limited(let holiday, let ends) = item else { return }
            cell.configure(holiday, ends: ends, selected: UIApplication.shared.alternateIconName == holiday.iconName)
        }
        let stockReg = UICollectionView.CellRegistration<IconCell, Item> { cell, _, item in
            guard case .stock(let name) = item else { return }
            cell.configure(image: UIImage(named: "Preview-" + (name ?? "AppIcon")), label: Self.label(for: name),
                           selected: UIApplication.shared.alternateIconName == name)
        }
        let headerReg = UICollectionView.SupplementaryRegistration<SectionHeader>(elementKind: SectionHeader.kind) { [unowned self] header, _, indexPath in
            switch dataSource.sectionIdentifier(for: indexPath.section) {
            case .limited: header.configure("Limited run", caption: "Here for the holiday")
            default: header.configure("Always printing")
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .hero: cv.dequeueConfiguredReusableCell(using: heroReg, for: indexPath, item: item)
            case .limited: cv.dequeueConfiguredReusableCell(using: limitedReg, for: indexPath, item: item)
            case .stock: cv.dequeueConfiguredReusableCell(using: stockReg, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath) }

        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        snap.appendSections([.hero]); snap.appendItems([.hero])
        let limited = Holiday.available()
        if !limited.isEmpty { snap.appendSections([.limited]); snap.appendItems(limited.map { .limited($0.0, $0.ends) }) }
        snap.appendSections([.stock]); snap.appendItems(Self.stock.map { .stock($0.name) })
        dataSource.apply(snap, animatingDifferences: false)
    }

    private static func label(for name: String?) -> String {
        stock.first { $0.name == name }?.label ?? Holiday.allCases.first { $0.iconName == name }?.title ?? "Amber"
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            let full = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120))
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .hero:
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: full, subitems: [NSCollectionLayoutItem(layoutSize: full)]))
                s.contentInsets = .init(top: 12, leading: 20, bottom: 24, trailing: 20)
                return s
            case .limited:
                let s = NSCollectionLayoutSection(group: .vertical(layoutSize: full, subitems: [NSCollectionLayoutItem(layoutSize: full)]))
                s.interGroupSpacing = 10
                s.contentInsets = .init(top: 10, leading: 16, bottom: 26, trailing: 16)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            default:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.2), heightDimension: .estimated(90)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(90)), subitems: [item])
                group.interItemSpacing = .fixed(10)
                let s = NSCollectionLayoutSection(group: group)
                s.contentInsets = .init(top: 10, leading: 16, bottom: 30, trailing: 16)
                s.boundarySupplementaryItems = [Layouts.headerItem()]
                return s
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let name: String?
        switch dataSource.itemIdentifier(for: indexPath) {
        case .limited(let holiday, _): name = holiday.iconName
        case .stock(let n): name = n
        default: return
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

/// The icon you have now, big and tilted, with its name.
private final class IconHeroCell: UICollectionViewCell {
    private let image = UIImageView()
    private let name = UILabel.make(Theme.display(32, weight: .black))

    override init(frame: CGRect) {
        super.init(frame: frame)
        image.layer.cornerRadius = 40
        image.layer.cornerCurve = .continuous
        image.clipsToBounds = true
        image.backgroundColor = Theme.surface
        image.transform = CGAffineTransform(rotationAngle: -0.1)
        name.textAlignment = .center
        let title = UILabel.make(Theme.display(52, weight: .black))
        title.text = "TICKET STOCK"
        let sub = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)
        sub.text = "Pick the paper your tickets are printed on. Your Home Screen follows."
        let stack = UIStackView(arrangedSubviews: [title, sub, image, name])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(26, after: sub)
        stack.setCustomSpacing(22, after: image)
        contentView.addSubview(stack)
        stack.pin(to: contentView)
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 170), image.heightAnchor.constraint(equalToConstant: 170)])
        sub.textAlignment = .center
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(image picture: UIImage?, name text: String) {
        image.image = picture
        name.text = text.uppercased()
    }
}

/// A holiday icon on offer: dashed edge, when it leaves, and the reassurance that nothing changes unless you tap it.
private final class LimitedIconCell: UICollectionViewCell {
    private let image = UIImageView()
    private let caption = UILabel.make(Theme.label(.caption2, weight: .bold), UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1))
    private let name = UILabel.make(Theme.display(28, weight: .black))
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let border = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        border.fillColor = nil
        border.lineWidth = 1.5
        border.lineDashPattern = [5, 4]
        contentView.layer.addSublayer(border)
        image.layer.cornerRadius = 15
        image.layer.cornerCurve = .continuous
        image.clipsToBounds = true
        note.text = "Yours to pick while it's here. Nothing changes unless you tap it."
        let text = UIStackView(arrangedSubviews: [caption, name, note])
        text.axis = .vertical
        text.spacing = 4
        let row = UIStackView(arrangedSubviews: [image, text])
        row.spacing = 14
        row.alignment = .center
        contentView.addSubview(row)
        row.pin(to: contentView, inset: 14)
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 66), image.heightAnchor.constraint(equalToConstant: 66)])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.path = UIBezierPath(roundedRect: contentView.bounds.insetBy(dx: 1, dy: 1), cornerRadius: 18).cgPath
    }

    func configure(_ holiday: Holiday, ends: Date, selected: Bool) {
        image.image = UIImage(named: "Preview-" + holiday.iconName)
        let last = ends.addingTimeInterval(-1).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        caption.setCaps(selected ? "On now · listed until \(last)" : "Limited run · until \(last)")
        name.text = holiday.title.uppercased()
        border.strokeColor = (selected ? Theme.accent : UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 0.5)).cgColor
        border.lineDashPattern = selected ? nil : [5, 4]
        accessibilityLabel = "\(holiday.title) icon, available until \(last)"
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}

private final class IconCell: UICollectionViewCell {
    private let image = UIImageView()
    private let label = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        image.layer.cornerRadius = 14
        image.layer.cornerCurve = .continuous
        image.clipsToBounds = true
        image.backgroundColor = Theme.surface
        image.layer.borderColor = Theme.accent.cgColor
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [image, label])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.pin(to: contentView)
        image.heightAnchor.constraint(equalTo: image.widthAnchor).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(image picture: UIImage?, label text: String, selected: Bool) {
        image.image = picture
        image.layer.borderWidth = selected ? 3 : 0
        image.alpha = selected ? 1 : 0.8
        label.setCaps(text)
        label.textColor = selected ? Theme.text : Theme.secondary
        accessibilityLabel = "\(text) icon"
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
