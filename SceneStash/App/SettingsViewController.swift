import CloudKit
import UIKit

final class SettingsViewController: UITableViewController {
    private enum Row { case region, services, icloud, replay, version }
    private let sections: [(String?, [Row], String?)] = [
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
