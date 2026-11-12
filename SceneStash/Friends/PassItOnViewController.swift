import CloudKit
import CoreData
import UIKit

/// Recommend: pick a friend, add a note, send. Friends are two-person iCloud shares, set up with Invite.
final class RecommendViewController: UIViewController {
    private let item: Title
    private var friends: [Friend] = []
    private var chosen: Friend?
    private let people = UIStackView()
    private let note = UITextField()
    private let send = CapsuleButton.primary("Send")

    init(title: Title) {
        item = title
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recommend"
        installBackdrop()
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })

        let poster = ArtView(radius: 8)
        poster.show(TMDB.imageURL(item.posterPath, .poster), name: item.name)
        let name = UILabel.make(Theme.text(.title3, weight: .semibold), Theme.text, lines: 2)
        name.text = item.name
        let mine = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 2)
        let tracked = Store.shared.tracked(item.id, item.mediaType)
        let seen = tracked?.viewings.count ?? 0
        mine.text = [tracked.flatMap { $0.rating > 0 ? "You rated it \($0.rating)" : nil }, seen > 1 ? "seen \(seen) times" : nil].compactMap { $0 }.joined(separator: " · ")
        let words = UIStackView(arrangedSubviews: [name, mine])
        words.axis = .vertical
        words.spacing = 2
        let top = UIStackView(arrangedSubviews: [poster, words])
        top.spacing = 14
        top.alignment = .center
        NSLayoutConstraint.activate([poster.widthAnchor.constraint(equalToConstant: 64), poster.heightAnchor.constraint(equalToConstant: 96)])

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        people.spacing = 16
        people.alignment = .top
        scroll.addSubview(people)
        people.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            people.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            people.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            people.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            people.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            people.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 84),
        ])

        note.attributedPlaceholder = NSAttributedString(string: "Add a note", attributes: [.foregroundColor: Theme.tertiary])
        note.font = Theme.text(.body)
        note.textColor = Theme.text
        Card.style(note)
        note.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        note.leftViewMode = .always
        note.returnKeyType = .done
        note.heightAnchor.constraint(equalToConstant: 44).isActive = true
        note.addAction(UIAction { [weak self] _ in self?.note.resignFirstResponder() }, for: .editingDidEndOnExit)
        send.addAction(UIAction { [weak self] _ in self?.sendIt() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [top, caption("To"), scroll, caption("Note"), note, send])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(22, after: top)
        stack.setCustomSpacing(18, after: scroll)
        stack.setCustomSpacing(18, after: note)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Shelf.margin),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
        ])
        render()
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    private func caption(_ text: String) -> UILabel {
        let l = UILabel.make(Theme.text(.footnote, weight: .semibold), Theme.secondary)
        l.text = text.uppercased()
        return l
    }

    @objc private func render() {
        friends = Store.shared.friends()
        if chosen == nil || !friends.contains(chosen!) { chosen = friends.first { Store.shared.friendName($0) != nil } }
        people.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, f) in friends.enumerated() {
            let name = Store.shared.friendName(f)
            people.addArrangedSubview(person(name.map { String($0.prefix(1)) } ?? "?", name ?? "Invited", color: Avatar.colors[(i + 1) % Avatar.colors.count], on: f == chosen) { [weak self] in
                self?.chosen = f
                Haptics.tap()
                self?.render()
            })
        }
        people.addArrangedSubview(person("+", "Invite", color: UIColor(white: 0.47, alpha: 0.34), on: false) { [weak self] in self?.inviteFriend() })
        let to = chosen.flatMap(Store.shared.friendName)
        send.configuration?.title = to.map { "Send to \($0)" } ?? (chosen == nil ? "Invite a Friend First" : "Send")
        send.isEnabled = chosen != nil
    }

    private func person(_ initial: String, _ name: String, color: UIColor, on: Bool, action: @escaping () -> Void) -> UIView {
        let disc = Avatar(initial, index: 0, size: 56)
        disc.backgroundColor = color
        disc.textColor = initial == "+" ? .white : .black
        disc.layer.borderColor = on ? Theme.accent.cgColor : UIColor.clear.cgColor
        disc.layer.borderWidth = on ? 3 : 0
        let label = UILabel.make(Theme.text(.caption1), on ? Theme.text : Theme.secondary)
        label.text = name
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [disc, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        let button = UIControl()
        button.addSubview(stack)
        stack.pin(to: button)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.isAccessibilityElement = true
        button.accessibilityTraits = on ? [.button, .selected] : .button
        button.accessibilityLabel = name
        return button
    }

    private func inviteFriend() {
        guard Store.cloudEnabled else { return }
        Haptics.tap()
        let friend = Store.shared.newFriend()
        invite(friend, title: "Pass It On in Scene Stash", from: people.arrangedSubviews.last)
    }

    private func sendIt() {
        guard let chosen else { return }
        Store.shared.recommend(item, to: chosen, note: note.text)
        Haptics.success()
        dismiss(animated: true)
    }
}

/// Pass It On, from Library: what friends passed you, what you passed on and how they rated it, your hit
/// rate, and your friends.
final class PassItOnViewController: UIViewController, UICollectionViewDelegate, UICloudSharingControllerDelegate {
    nonisolated private enum Section: Hashable { case hits, received, sent, friends }
    nonisolated private enum Item: Hashable { case hits, rec(NSManagedObjectID), friend(NSManagedObjectID), invite }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout { [weak self] index, env in
        var c = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        c.backgroundColor = .clear
        c.headerMode = self?.dataSource?.sectionIdentifier(for: index) == .hits ? .none : .supplementary
        return NSCollectionLayoutSection.list(using: c, layoutEnvironment: env)
    })
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pass It On"
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .always
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.pin(to: view)
        let cellReg = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [unowned self] cell, _, item in
            cell.contentConfiguration = content(for: item, cell.defaultContentConfiguration())
            cell.accessories = item == .hits ? [] : [.disclosureIndicator()]
        }
        let headerReg = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [unowned self] header, _, ip in
            var c = UIListContentConfiguration.header()
            switch dataSource.sectionIdentifier(for: ip.section) {
            case .received: c.text = "Passed to You"
            case .sent: c.text = "You Passed On"
            default: c.text = "Friends"
            }
            header.contentConfiguration = c
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, ip, item in cv.dequeueConfiguredReusableCell(using: cellReg, for: ip, item: item) }
        dataSource.supplementaryViewProvider = { cv, _, ip in cv.dequeueConfiguredReusableSupplementary(using: headerReg, for: ip) }
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    @objc private func reload() {
        let recs = Store.shared.recommendations()
        var snap = NSDiffableDataSourceSnapshot<Section, Item>()
        if Store.shared.hitRate().rated > 0 { snap.appendSections([.hits]); snap.appendItems([.hits]) }
        let received = recs.filter { !$0.isMine }, sent = recs.filter(\.isMine)
        if !received.isEmpty { snap.appendSections([.received]); snap.appendItems(received.map { .rec($0.objectID) }) }
        if !sent.isEmpty { snap.appendSections([.sent]); snap.appendItems(sent.map { .rec($0.objectID) }) }
        snap.appendSections([.friends])
        snap.appendItems(Store.shared.friends().map { .friend($0.objectID) } + [.invite])
        snap.reconfigureItems(snap.itemIdentifiers.filter { Set(dataSource.snapshot().itemIdentifiers).contains($0) })
        dataSource.apply(snap, animatingDifferences: view.window != nil)
    }

    private func object<T>(_ id: NSManagedObjectID) -> T? { try? Store.shared.context.existingObject(with: id) as? T }

    private func content(for item: Item, _ base: UIListContentConfiguration) -> UIListContentConfiguration {
        var c = base
        c.secondaryTextProperties.color = Theme.secondary
        c.imageProperties.tintColor = Theme.accent
        switch item {
        case .hits:
            let (hits, rated) = Store.shared.hitRate()
            c = .valueCell()
            c.text = "Your Hit Rate"
            c.secondaryText = "\(hits) of \(rated)"
            c.secondaryTextProperties.font = Theme.text(.title3, weight: .bold)
            c.secondaryTextProperties.color = Theme.text
        case .rec(let id):
            guard let rec: Recommendation = object(id) else { return c }
            c.text = rec.name
            c.image = UIImage(systemName: rec.title.mediaType == .tv ? "tv" : "film")
            let note = rec.note.map { "“\($0)”" }
            if rec.isMine {
                let to = rec.friend.flatMap(Store.shared.friendName) ?? "a friend"
                let back = rec.rating > 0 ? "\(to) rated it \(rec.rating)" + (rec.line.map { " · “\($0)”" } ?? "") : "Sent to \(to) · not watched yet"
                c.secondaryText = back
            } else {
                c.secondaryText = ["From \(rec.authorName ?? "a friend")" + (rec.senderRating > 0 ? " · they rated it \(rec.senderRating)" : ""), note].compactMap { $0 }.joined(separator: "\n")
            }
        case .friend(let id):
            guard let friend: Friend = object(id) else { return c }
            let name = Store.shared.friendName(friend)
            c.text = name ?? "Invited"
            c.secondaryText = name == nil ? "Waiting for them to accept" : "\(friend.recs?.count ?? 0) passed on between you"
            c.image = UIImage(systemName: "person.crop.circle")
        case .invite:
            c.text = "Invite a Friend"
            c.textProperties.color = Theme.accent
            c.image = UIImage(systemName: "person.badge.plus")
        }
        return c
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .hits
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .rec(let id):
            if let rec: Recommendation = object(id) { openDetail(rec.title) { [weak self] in self?.dataSource.indexPath(for: .rec(id)).flatMap { collectionView.cellForItem(at: $0) } } }
        case .friend(let id):
            guard let friend: Friend = object(id) else { return }
            if let share = Store.shared.share(for: friend) {
                let controller = UICloudSharingController(share: share, container: Store.shared.cloudContainer)
                controller.delegate = self
                present(controller, animated: true)
            } else {
                invite(friend, title: "Pass It On in Scene Stash", from: collectionView.cellForItem(at: indexPath))
            }
        case .invite:
            guard Store.cloudEnabled else { return }
            invite(Store.shared.newFriend(), title: "Pass It On in Scene Stash", from: collectionView.cellForItem(at: indexPath))
        default: break
        }
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { "Pass It On" }
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { showError(error) }
}
