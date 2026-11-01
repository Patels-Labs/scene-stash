import CloudKit
import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row { case pass, icon, region, services, icloud, replay, version }
    private let sections: [(String?, [Row], String?)] = [
        ("All-Access Pass", [.pass, .icon], nil),
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
        cell.selectionStyle = .default
        switch sections[indexPath.section].1[indexPath.row] {
        case .pass:
            let pass = Pass.shared
            config.text = pass.owned ? "All-Access Pass" : "Get the All-Access Pass"
            if pass.owned {
                config.secondaryText = "Lifetime"
            } else if pass.trialActive, let ends = pass.trialEnds {
                let days = max(Calendar.current.dateComponents([.day], from: .now, to: ends).day ?? 0, 0) + 1
                config.secondaryText = "Trial · \(days) day\(days == 1 ? "" : "s") left"
            } else {
                config.secondaryText = pass.lifetime?.displayPrice ?? "$1.99"
            }
            config.image = UIImage(systemName: "ticket.fill")
            cell.accessoryType = .disclosureIndicator
        case .icon:
            config.text = "App icon"
            config.secondaryText = Pass.shared.isUnlocked ? nil : "Pass"
            config.image = UIImage(systemName: Pass.shared.isUnlocked ? "app.badge" : "lock.fill")
            cell.accessoryType = .disclosureIndicator
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

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].1[indexPath.row] {
        case .pass: present(PaywallViewController(), animated: true)
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

/// Alternate ticket icons, one of the pass's extras.
final class IconPickerViewController: UICollectionViewController {
    private static let icons: [(name: String?, label: String)] = [
        (nil, "Amber"), ("AppIcon-Red", "Red"), ("AppIcon-Teal", "Teal"), ("AppIcon-Silver", "Silver"), ("AppIcon-Ink", "Ink"),
    ]

    init() {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / 3), heightDimension: .fractionalHeight(1)))
        item.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.42)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 16, leading: 12, bottom: 16, trailing: 12)
        super.init(collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App icon"
        collectionView.backgroundColor = Theme.bg
        collectionView.register(IconCell.self, forCellWithReuseIdentifier: "icon")
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { Self.icons.count }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "icon", for: indexPath) as! IconCell
        let icon = Self.icons[indexPath.item]
        cell.configure(image: UIImage(named: "Preview-" + (icon.name ?? "AppIcon")), label: icon.label,
                       selected: UIApplication.shared.alternateIconName == icon.name)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let name = Self.icons[indexPath.item].name
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                Haptics.success()
                self?.collectionView.reloadData()
            }
        }
    }
}

private final class IconCell: UICollectionViewCell {
    private let image = UIImageView()
    private let label = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        image.layer.cornerRadius = 22
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
        label.setCaps(text)
        label.textColor = selected ? Theme.text : Theme.secondary
        accessibilityLabel = "\(text) icon"
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
