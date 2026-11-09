import CloudKit
import CoreData
import UIKit

/// One night out, Apple TV-style: the film's art and logo with Directions and Invite Friends, then where the
/// evening's got to, your ticket, who's going, and once it's finished, everyone's reactions.
final class NightViewController: UIViewController, UICloudSharingControllerDelegate {
    private let night: MovieNight
    private var clock: Timer?
    private var creatingShare = false

    private let hero = HeroView()
    private let primary = CapsuleButton.primary("Directions", image: "location.fill")
    private let invite = CapsuleButton.glass("Invite Friends", image: "person.badge.plus")
    private let booked = CapsuleButton.circle("ticket", label: "Mark as Booked")
    private let steps = UIStackView()
    private let ticket = TicketCard()
    private let people = UIStackView()
    private let after = UIView()
    private let afterDetail = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private var afterSection: UIView!
    private let reactions = UIStackView()
    private let notes = UIStackView()
    private let myLine = UITextField()
    private let myRating = RatingRow(inset: 0)

    init(night: MovieNight) {
        self.night = night
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.menuItems() ?? [])
        }]))

        buildHero()
        buildSteps()
        buildAfter()
        buildReactions()
        afterSection = section("After the Film", after)

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.bottom = 100
        view.addSubview(scroll)
        // The page ends at the keyboard, so Reactions can scroll up above it while you type.
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self, weak scroll] _ in
            MainActor.assumeIsolated {
                guard let self, let scroll, self.myLine.isFirstResponder else { return }
                scroll.scrollRectToVisible(self.myLine.convert(self.myLine.bounds.insetBy(dx: 0, dy: -24), to: scroll), animated: true)
            }
        }
        let page = UIStackView(arrangedSubviews: [hero, padded(steps), section("Your Ticket", ticket), section("Who's Going", peopleRow(), inset: false),
                                                  afterSection, reactions])
        page.axis = .vertical
        page.spacing = 28
        scroll.addSubview(page)
        page.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            page.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            page.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        render()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.render() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clock?.invalidate()
    }

    @objc private func storeChanged() {
        // A friend deleted the night, or you left it.
        guard !night.isDeleted, night.managedObjectContext != nil else { navigationController?.popViewController(animated: true); return }
        // Sharing moves the night into its own zone and fires a burst of changes; looking up the share
        // mid-move can block, so wait until it's done.
        guard !creatingShare else { return }
        render()
    }

    // MARK: Building

    private func padded(_ view: UIView) -> UIView {
        let box = UIView()
        box.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: box.topAnchor),
            view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: Shelf.margin),
            view.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -Shelf.margin),
        ])
        return box
    }

    private func section(_ title: String, _ body: UIView, inset: Bool = true) -> UIView {
        let label = UILabel.make(Theme.text(.title2, weight: .semibold))
        label.text = title
        label.accessibilityTraits = .header
        let stack = UIStackView(arrangedSubviews: [padded(label), inset ? padded(body) : body])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    private func buildHero() {
        hero.show(night.title, meta: nil)
        primary.widthAnchor.constraint(equalToConstant: 255).isActive = true
        invite.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let row = UIStackView(arrangedSubviews: [invite, booked])
        row.spacing = 10
        row.alignment = .center
        [primary, row].forEach(hero.content.addArrangedSubview)
        hero.content.setCustomSpacing(10, after: primary)
        primary.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            night.cinema == nil ? edit() : directions()
        }, for: .primaryActionTriggered)
        invite.addAction(UIAction { [weak self] action in self?.inviteFriends(from: action.sender as? UIView) }, for: .primaryActionTriggered)
        booked.addAction(UIAction { [weak self] _ in self?.toggleBooked() }, for: .primaryActionTriggered)
    }

    private func buildSteps() {
        Card.style(steps)
        steps.distribution = .fillEqually
        steps.alignment = .top
        steps.spacing = 6
        steps.isLayoutMarginsRelativeArrangement = true
        steps.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    private func peopleRow() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInset = .init(top: 0, left: Shelf.margin, bottom: 0, right: Shelf.margin)
        people.spacing = Shelf.gap
        people.alignment = .top
        scroll.addSubview(people)
        people.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            people.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            people.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            people.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            people.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            people.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: Shelf.poster.width + 52),
        ])
        return scroll
    }

    private func buildAfter() {
        Card.style(after)
        let library = Self.fact(symbol: "checkmark", tint: Theme.accent, title: "Added to everyone's library", detail: afterDetail)
        let react = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
        react.text = "One line and a rating each, the same rating as the film's page. Kept in Past Nights."
        let reactions = Self.fact(symbol: "text.bubble", tint: UIColor(red: 0.56, green: 0.83, blue: 0.86, alpha: 1), title: "Reactions", detail: react)
        let rule = UIView()
        rule.backgroundColor = Card.rule
        rule.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let stack = UIStackView(arrangedSubviews: [library, rule, reactions])
        stack.axis = .vertical
        after.addSubview(stack)
        stack.pin(to: after)
    }

    private static func fact(symbol: String, tint: UIColor, title: String, detail: UILabel) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.backgroundColor = tint.withAlphaComponent(0.18)
        icon.layer.cornerRadius = 8
        icon.preferredSymbolConfiguration = .init(pointSize: 14, weight: .semibold)
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let t = UILabel.make(Theme.text(.body), Theme.text, lines: 0)
        t.text = title
        let text = UIStackView(arrangedSubviews: [t, detail])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 14
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        return row
    }

    private func buildReactions() {
        myLine.attributedPlaceholder = NSAttributedString(string: "Your one line", attributes: [.foregroundColor: Theme.tertiary])
        myLine.font = Theme.text(.body)
        myLine.textColor = Theme.text
        Card.style(myLine)
        myLine.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        myLine.leftViewMode = .always
        myLine.returnKeyType = .done
        myLine.accessibilityLabel = "Your reaction"
        myLine.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        myLine.addAction(UIAction { [weak self] _ in self?.saveMyLine(); self?.myLine.resignFirstResponder() }, for: .editingDidEndOnExit)
        myLine.addAction(UIAction { [weak self] _ in self?.saveMyLine() }, for: .editingDidEnd)
        myRating.onChange = { [weak self] _ in self?.saveMyLine() }
        notes.axis = .vertical
        Card.style(notes)
        let yours = UILabel.make(Theme.text(.headline))
        yours.text = "Yours"
        let body = UIStackView(arrangedSubviews: [notes, yours, myLine, myRating])
        body.axis = .vertical
        body.spacing = 12
        body.setCustomSpacing(24, after: notes)
        reactions.addArrangedSubview(section("Reactions", body))
    }

    // MARK: Rendering

    private func render() {
        let stage = night.status()
        if let uuid = night.uuid, (stage == .lightsDown && !Prefs.watchingNights.contains(uuid)) || (stage == .creditsRolled && !Prefs.stashedNights.contains(uuid)) {
            // Next turn of the run loop: updating saves, and saving re-renders.
            DispatchQueue.main.async { Store.shared.updateFromNights() }
        }
        let showtime = night.showtime ?? .now
        let crew = Store.shared.guests(for: night)
        let day = showtime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        hero.meta.text = "Movie Night · \(day)" + (crew.count > 1 ? " · \(crew.count) going" : "")
        hero.meta.isHidden = false

        primary.configuration?.title = night.cinema == nil ? "Add a Cinema" : "Directions"
        primary.configuration?.image = UIImage(systemName: night.cinema == nil ? "plus" : "location.fill")
        primary.isHidden = stage == .creditsRolled
        invite.isHidden = stage == .creditsRolled || night.isGuest
        booked.isHidden = stage != .noTickets && stage != .ticketsInHand
        booked.configuration?.image = UIImage(systemName: night.booked ? "ticket.fill" : "ticket")
        booked.configuration?.baseForegroundColor = night.booked ? Theme.accent : .white
        booked.accessibilityLabel = night.booked ? "Booked. Double tap to mark as not booked" : "Mark as Booked"

        steps.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for step in NightStatus.allCases {
            steps.addArrangedSubview(StepView(step, sub: stepNote(step), state: step.rawValue < stage.rawValue ? .done : step == stage ? .now : .todo))
        }

        ticket.configure(night)

        people.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, guest) in crew.enumerated() {
            let role = guest.planned ? "Planned it" : guest.accepted ? "Going" : "Invited"
            people.addArrangedSubview(PersonView(initial: guest.initial, color: Avatar.colors[i % Avatar.colors.count], name: guest.name, detail: role))
        }

        afterSection.isHidden = stage == .creditsRolled
        let lightsUp = night.lightsUp.map { $0.formatted(date: .omitted, time: .shortened) } ?? "the end"
        afterDetail.text = "Watching at \(showtime.formatted(date: .omitted, time: .shortened)), Watched at about \(lightsUp)"

        reactions.isHidden = stage != .creditsRolled
        if stage == .creditsRolled { renderNotes() }
    }

    private func stepNote(_ step: NightStatus) -> String {
        let time: (Date?) -> String = { $0?.formatted(date: .omitted, time: .shortened) ?? "" }
        switch step {
        case .noTickets: return (night.createdAt ?? .now).formatted(.dateTime.day().month(.abbreviated))
        case .ticketsInHand: return night.booked ? (night.bookedBy ?? "Yes") : "Not yet"
        case .lightsDown: return time(night.showtime)
        case .creditsRolled: return "~" + time(night.lightsUp)
        }
    }

    private func renderNotes() {
        notes.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let all = (night.notes ?? []).filter { $0.authorID != Prefs.me && ($0.text != nil || $0.rating > 0) }
            .sorted { ($0.createdAt ?? .now) < ($1.createdAt ?? .now) }
        for (i, n) in all.enumerated() {
            notes.addArrangedSubview(ReactionRow(initial: String((n.authorName ?? "A").prefix(1)), color: Avatar.colors[(i + 1) % Avatar.colors.count],
                                                 line: n.text, name: n.authorName ?? "A friend", rating: Int(n.rating), divider: i > 0))
        }
        notes.isLayoutMarginsRelativeArrangement = all.isEmpty
        if all.isEmpty {
            let empty = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)
            empty.text = "No reactions from friends yet."
            notes.addArrangedSubview(empty)
            notes.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        }
        // Yours is the film's rating and line, wherever you set them.
        let film = Store.shared.tracked(night.title.id, .movie)
        let mine = Store.shared.myNote(on: night)
        let line = mine?.text ?? film?.note, rating = Int(mine?.rating ?? film?.rating ?? 0)
        if !myLine.isFirstResponder { myLine.text = line }
        if myRating.value != rating { myRating.set(rating) }
    }

    // MARK: Actions

    private func toggleBooked() {
        night.booked.toggle()
        night.bookedBy = night.booked ? Store.shared.myName(on: night) : nil
        Store.shared.save()
        Haptics.success()
    }

    private func saveMyLine() {
        let mine = Store.shared.myNote(on: night)
        guard mine == nil || myLine.text != mine?.text || myRating.value != Int(mine?.rating ?? 0) else { return }
        guard mine != nil || !(myLine.text ?? "").isEmpty || myRating.value > 0 else { return }
        Store.shared.setNote(myLine.text, rating: myRating.value, on: night, as: Store.shared.myName(on: night))
    }

    private func directions() {
        let query = [night.cinema, night.address].compactMap { $0 }.joined(separator: ", ")
        var comps = URLComponents(string: "https://maps.apple.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = comps.url { UIApplication.shared.open(url) }
    }

    private func edit() {
        present(UINavigationController(rootViewController: NightFormViewController(night: night)), animated: true)
    }

    private func menuItems() -> [UIMenuElement] {
        var items: [UIMenuElement] = [UIAction(title: "Edit Details", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.edit() }]
        if Store.shared.share(for: night) != nil {
            items.append(UIAction(title: night.isGuest ? "People and Leaving" : "Manage People", image: UIImage(systemName: "person.2")) { [weak self] _ in self?.managePeople() })
        }
        if !night.isGuest {
            items.append(UIAction(title: "Delete Night", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() })
        }
        return items
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Delete this night?", message: "It's removed for everyone you invited too.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete Night", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Store.shared.delete(night)
            navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: Sharing

    private func inviteFriends(from sender: UIView?) {
        guard Store.cloudEnabled else {
            let alert = UIAlertController(title: "Needs iCloud", message: "Inviting friends works on iPhone with iCloud on.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        if let share = Store.shared.share(for: night) { presentInvite(share, from: sender); return }
        // Make the share before the sheet opens: creating it from inside the sheet hid the real error and could hang.
        creatingShare = true
        invite.configuration?.showsActivityIndicator = true
        invite.isEnabled = false
        let id = night.objectID
        Task {
            defer {
                creatingShare = false
                invite.configuration?.showsActivityIndicator = false
                invite.isEnabled = true
                render()
            }
            do {
                presentInvite(try await Store.shared.makeShare(for: id), from: sender)
            } catch {
                let ns = error as NSError
                let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\n\($0.localizedDescription) (\($0.domain) \($0.code))" } ?? ""
                let alert = UIAlertController(title: "Couldn't create the invite",
                                              message: "\(ns.localizedDescription) (\(ns.domain) \(ns.code))\(underlying)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func presentInvite(_ share: CKShare, from sender: UIView?) {
        let provider = NSItemProvider()
        // Read and write for everyone; you choose whether it's only people you add or anyone with the link.
        let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .any)
        provider.registerCKShare(share, container: Store.shared.cloudContainer, allowedSharingOptions: options)
        let sheet = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [provider]))
        sheet.popoverPresentationController?.sourceView = sender
        present(sheet, animated: true)
    }

    private func managePeople() {
        guard let share = Store.shared.share(for: night) else { return }
        let controller = UICloudSharingController(share: share, container: Store.shared.cloudContainer)
        controller.delegate = self
        present(controller, animated: true)
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { night.name }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        showError(error)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { render() }
}

/// One stage of the night: a bar that fills as the evening moves on, with its name and when.
private final class StepView: UIStackView {
    enum State { case done, now, todo }

    init(_ step: NightStatus, sub: String, state: State) {
        super.init(frame: .zero)
        let bar = UIView()
        bar.layer.cornerRadius = 2
        bar.backgroundColor = state == .todo ? UIColor(white: 0.47, alpha: 0.36) : Theme.accent.withAlphaComponent(state == .now ? 1 : 0.5)
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        let name = UILabel.make(Theme.text(.footnote, weight: .semibold), state == .now ? Theme.accent : state == .done ? Theme.text : Theme.secondary, lines: 0)
        name.text = step.label
        let when = UILabel.make(Theme.text(.caption1), Theme.secondary, lines: 0)
        when.text = sub
        [bar, name, when].forEach(addArrangedSubview)
        axis = .vertical
        spacing = 6
        setCustomSpacing(8, after: bar)
        isAccessibilityElement = true
        accessibilityLabel = "\(step.label), \(sub)" + (state == .now ? ", now" : "")
    }
    required init(coder: NSCoder) { fatalError() }
}

/// Lays a view out inside a box's layout margins.
private func margined(_ view: UIView, _ margins: NSDirectionalEdgeInsets) -> UIView {
    let box = UIView()
    box.directionalLayoutMargins = margins
    box.addSubview(view)
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: box.layoutMarginsGuide.topAnchor),
        view.bottomAnchor.constraint(equalTo: box.layoutMarginsGuide.bottomAnchor),
        view.leadingAnchor.constraint(equalTo: box.layoutMarginsGuide.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: box.layoutMarginsGuide.trailingAnchor),
    ])
    return box
}

/// The ticket: the cinema, then screen, seats and showtime, and when the film really starts.
private final class TicketCard: UIView {
    private let cinema = UILabel.make(Theme.text(.body), Theme.text, lines: 0)
    private let address = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let screen = UILabel.make(Theme.text(.title1, weight: .bold))
    private let seats = UILabel.make(Theme.text(.title1, weight: .bold))
    private let time = UILabel.make(Theme.text(.title1, weight: .bold))
    private let footnote = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private static let cellMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        Card.style(self)
        seats.adjustsFontSizeToFitWidth = true
        seats.minimumScaleFactor = 0.5
        let grid = UIStackView(arrangedSubviews: [Self.block("Screen", [screen]), Self.block("Seats", [seats]), Self.block("Showtime", [time])])
        grid.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [Self.block("Cinema", [cinema, address]), Self.rule(), grid, Self.rule(), margined(footnote, Self.cellMargins)])
        stack.axis = .vertical
        addSubview(stack)
        stack.pin(to: self)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func block(_ caption: String, _ values: [UILabel]) -> UIView {
        let label = UILabel.make(Theme.text(.footnote), Theme.secondary)
        label.text = caption
        let stack = UIStackView(arrangedSubviews: [label] + values)
        stack.axis = .vertical
        stack.spacing = 2
        return margined(stack, cellMargins)
    }

    private static func rule() -> UIView {
        let r = UIView()
        r.backgroundColor = Card.rule
        r.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return r
    }

    func configure(_ night: MovieNight) {
        cinema.text = night.cinema ?? "No cinema yet"
        address.text = night.address
        address.isHidden = night.address == nil
        screen.text = night.screen ?? "–"
        seats.text = night.seats ?? "–"
        let showtime = night.showtime ?? .now
        time.text = showtime.formatted(date: .omitted, time: .shortened)
        let starts = NightStatus.filmStarts(showtime).formatted(date: .omitted, time: .shortened)
        footnote.text = "Film starts about \(starts) after ads and trailers" + (night.lightsUp.map { " · out by \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
    }
}

/// A friend on the night: a coloured circle with their initial, their name, and how they're involved.
private final class PersonView: UIStackView {
    init(initial: String, color: UIColor, name: String, detail: String) {
        super.init(frame: .zero)
        let circle = UILabel.make(Theme.text(.largeTitle, weight: .bold), .black)
        circle.text = initial
        circle.textAlignment = .center
        circle.backgroundColor = color
        circle.layer.cornerRadius = Shelf.poster.width / 2
        circle.clipsToBounds = true
        circle.widthAnchor.constraint(equalToConstant: Shelf.poster.width).isActive = true
        circle.heightAnchor.constraint(equalToConstant: Shelf.poster.width).isActive = true
        let n = UILabel.make(Theme.text(.footnote))
        n.text = name
        n.textAlignment = .center
        let d = UILabel.make(Theme.text(.caption1), Theme.secondary)
        d.text = detail
        d.textAlignment = .center
        [circle, n, d].forEach(addArrangedSubview)
        axis = .vertical
        spacing = 2
        setCustomSpacing(8, after: circle)
        isAccessibilityElement = true
        accessibilityLabel = "\(name), \(detail)"
    }
    required init(coder: NSCoder) { fatalError() }
}

/// A friend's reaction: their initial, their one line, their name, and their rating.
private final class ReactionRow: UIView {
    init(initial: String, color: UIColor, line: String?, name: String, rating: Int, divider: Bool) {
        super.init(frame: .zero)
        let avatar = Avatar(initial, index: 0, size: 34)
        avatar.backgroundColor = color
        let text = UILabel.make(Theme.text(.body), Theme.text, lines: 0)
        text.text = line ?? "Just a rating"
        let who = UILabel.make(Theme.text(.footnote), Theme.secondary)
        who.text = name
        let words = UIStackView(arrangedSubviews: [text, who])
        words.axis = .vertical
        words.spacing = 2
        let score = UILabel.make(Theme.text(.title2, weight: .bold), Theme.accent)
        score.text = rating > 0 ? "\(rating)" : nil
        score.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [avatar, words, score])
        row.spacing = 12
        row.alignment = .center
        let box = margined(row, .init(top: 12, leading: 16, bottom: 12, trailing: 16))
        addSubview(box)
        box.pin(to: self)
        if divider {
            let rule = UIView()
            rule.backgroundColor = Card.rule
            addSubview(rule)
            rule.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rule.topAnchor.constraint(equalTo: topAnchor), rule.heightAnchor.constraint(equalToConstant: 0.5),
                rule.leadingAnchor.constraint(equalTo: words.leadingAnchor), rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        isAccessibilityElement = true
        accessibilityLabel = [name, line, rating > 0 ? "rated \(rating)" : nil].compactMap { $0 }.joined(separator: ", ")
    }
    required init?(coder: NSCoder) { fatalError() }
}
