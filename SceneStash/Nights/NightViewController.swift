import CoreData
import CloudKit
import UIKit

/// One night out as a group ticket: where it's moved to, the cinema and seats, who's going,
/// and once the credits roll, one line each for the scrapbook.
final class NightViewController: UIViewController, UICloudSharingControllerDelegate {
    private let night: MovieNight
    private var clock: Timer?

    private let glow = GlowView()
    private let poster = UIImageView()
    private let kicker = UILabel.make(Theme.label(), Theme.accent)
    private let when = UILabel.make(Theme.label(), Theme.secondary)
    private let titleLabel = UILabel.make(Theme.display(64, weight: .black), Theme.text, lines: 0)
    private let track = UIStackView()
    private let ticket = TicketCard()
    private let bookIt = PillButton("We've got tickets", image: "ticket")
    private let guests = UIStackView()
    private let invite = PillButton("Invite in Messages", image: "person.badge.plus", inverted: true)
    private let runsItself = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let scrapbook = UIStackView()
    private let notes = UIStackView()
    private let myLine = UITextField()
    private let myRating = ReelRatingView()

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

        view.addSubview(glow)
        glow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glow.topAnchor.constraint(equalTo: view.topAnchor), glow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glow.trailingAnchor.constraint(equalTo: view.trailingAnchor), glow.heightAnchor.constraint(equalToConstant: 560),
        ])
        glow.show(TMDB.imageURL(night.posterPath, .poster))

        let stack = UIStackView(arrangedSubviews: [header(), titleLabel, track, ticket, bookIt, section("Who's going", guests), invite, note(runsItself, caption: "Runs itself"), scrapbook])
        stack.axis = .vertical
        stack.spacing = 18
        stack.setCustomSpacing(26, after: titleLabel)
        stack.setCustomSpacing(30, after: bookIt)
        stack.setCustomSpacing(30, after: invite)
        stack.setCustomSpacing(30, after: stack.arrangedSubviews[7])
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -48),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        titleLabel.accessibilityTraits = .header
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        track.distribution = .fillEqually
        track.spacing = 6
        track.alignment = .top
        guests.axis = .vertical
        notes.axis = .vertical
        ticket.onDirections = { [weak self] in self?.directions() }
        bookIt.addAction(UIAction { [weak self] _ in self?.markBooked() }, for: .primaryActionTriggered)
        invite.addAction(UIAction { [weak self] action in self?.inviteFriends(from: action.sender as? UIView) }, for: .primaryActionTriggered)
        buildScrapbook()

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
        render()
    }

    // MARK: Building

    private func header() -> UIView {
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 12
        poster.backgroundColor = Theme.surface
        poster.transform = CGAffineTransform(rotationAngle: -0.05)
        poster.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([poster.widthAnchor.constraint(equalToConstant: 110), poster.heightAnchor.constraint(equalToConstant: 165)])
        poster.setImage(TMDB.imageURL(night.posterPath, .poster))
        let labels = UIStackView(arrangedSubviews: [kicker, when])
        labels.axis = .vertical
        labels.spacing = 8
        let row = UIStackView(arrangedSubviews: [poster, labels])
        row.spacing = 16
        row.alignment = .bottom
        return row
    }

    private func section(_ title: String, _ body: UIView) -> UIView {
        let label = UILabel.make(Theme.label(), Theme.tertiary)
        label.setCaps(title)
        let stack = UIStackView(arrangedSubviews: [label, body])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private func note(_ body: UILabel, caption: String) -> UIView {
        let label = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.accent)
        label.setCaps(caption)
        let stack = UIStackView(arrangedSubviews: [label, body])
        stack.axis = .vertical
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        stack.backgroundColor = Theme.accent.withAlphaComponent(0.1)
        stack.layer.cornerRadius = 16
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Theme.accent.withAlphaComponent(0.4).cgColor
        return stack
    }

    private func buildScrapbook() {
        myLine.attributedPlaceholder = NSAttributedString(string: "Your one line. Say it once, say it well.", attributes: [.foregroundColor: Theme.tertiary])
        myLine.font = Self.handwriting
        myLine.textColor = Theme.text
        myLine.backgroundColor = Theme.surface
        myLine.layer.cornerRadius = 12
        myLine.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        myLine.leftViewMode = .always
        myLine.returnKeyType = .done
        myLine.accessibilityLabel = "Your line"
        myLine.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        myLine.addAction(UIAction { [weak self] _ in self?.saveMyLine(); self?.myLine.resignFirstResponder() }, for: .editingDidEndOnExit)
        myLine.addAction(UIAction { [weak self] _ in self?.saveMyLine() }, for: .editingDidEnd)
        myRating.onChange = { [weak self] _ in self?.saveMyLine() }
        let rateLabel = UILabel.make(Theme.label(), Theme.tertiary)
        rateLabel.setCaps("Your rating")
        [section("One line each", notes), myLine, rateLabel, myRating].forEach(scrapbook.addArrangedSubview)
        scrapbook.axis = .vertical
        scrapbook.spacing = 12
        scrapbook.setCustomSpacing(18, after: myLine)
    }

    // MARK: Rendering

    private func render() {
        let stage = night.status()
        if stage == .creditsRolled, let uuid = night.uuid, !Prefs.stashedNights.contains(uuid) {
            // Next turn of the run loop: stashing saves, and saving re-renders.
            DispatchQueue.main.async { Store.shared.stashFinishedNights() }
        }
        let showtime = night.showtime ?? .now
        let crew = Store.shared.guests(for: night)
        kicker.setCaps(crew.count > 1 ? "Night out · \(crew.count) going" : "Night out")
        when.setCaps(showtime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · " + showtime.formatted(date: .omitted, time: .shortened))
        titleLabel.setDisplay(night.name?.uppercased(), lineHeight: 0.84)

        track.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for step in NightStatus.allCases {
            track.addArrangedSubview(StepView(step, sub: stepNote(step), state: step.rawValue < stage.rawValue ? .done : step == stage ? .now : .todo))
        }

        ticket.configure(night, admit: crew.count)
        bookIt.isHidden = stage != .noTickets

        guests.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, guest) in crew.enumerated() {
            let note = guest.planned ? "Planned it" : guest.accepted ? nil : "Invited"
            guests.addArrangedSubview(PersonRow(Avatar(guest.initial, index: i, size: 34), name: guest.name, trailing: note))
        }
        invite.isHidden = stage == .creditsRolled || night.isGuest

        let lightsUp = night.lightsUp.map { $0.formatted(date: .omitted, time: .shortened) } ?? "the end"
        runsItself.text = stage == .creditsRolled
            ? "The film's in your stash as seen. Add your line for the scrapbook below."
            : "Turns to Lights down at \(showtime.formatted(date: .omitted, time: .shortened)) and Credits rolled around \(lightsUp). The film then goes into everyone's stash as seen."

        scrapbook.isHidden = stage != .creditsRolled
        if stage == .creditsRolled { renderNotes() }
    }

    private func stepNote(_ step: NightStatus) -> String {
        let time: (Date?) -> String = { $0?.formatted(date: .omitted, time: .shortened) ?? "" }
        switch step {
        case .noTickets: return "Planned " + (night.createdAt ?? .now).formatted(.dateTime.day().month(.abbreviated))
        case .ticketsInHand: return night.booked ? (night.bookedBy.map { "\($0) booked" } ?? "Booked") : "Not yet"
        case .lightsDown: return "Auto · " + time(night.showtime)
        case .creditsRolled: return "Auto · ~" + time(night.lightsUp)
        }
    }

    private func renderNotes() {
        notes.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let all = (night.notes ?? []).filter { $0.text != nil || $0.rating > 0 }.sorted { ($0.createdAt ?? .now) < ($1.createdAt ?? .now) }
        for (i, n) in all.enumerated() {
            let mine = n.authorID == Prefs.me
            let name = mine ? "You" : n.authorName ?? "A friend"
            let row = PersonRow(Avatar(String(name.prefix(1)), index: i, size: 30), name: n.text ?? "No words, just a rating",
                                trailing: n.rating > 0 ? "\(n.rating)" : nil, caption: name)
            row.name.font = Self.handwriting
            row.name.numberOfLines = 0
            notes.addArrangedSubview(row)
        }
        if all.isEmpty {
            let empty = UILabel.make(Theme.text(.subheadline), Theme.tertiary, lines: 0)
            empty.text = "Nobody's written theirs yet. Go first."
            notes.addArrangedSubview(empty)
        }
        let mine = Store.shared.myNote(on: night)
        if !myLine.isFirstResponder { myLine.text = mine?.text }
        if !myRating.isInteracting, myRating.value != Int(mine?.rating ?? 0) { myRating.set(Int(mine?.rating ?? 0), animated: false) }
    }

    private static let handwriting: UIFont = {
        let base = UIFont.systemFont(ofSize: 20, weight: .medium)
        let font = base.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: 20) } ?? base
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }()

    // MARK: Actions

    private func markBooked() {
        night.booked = true
        night.bookedBy = Store.shared.myName(on: night)
        Store.shared.save()
        Haptics.success()
    }

    private func saveMyLine() {
        let mine = Store.shared.myNote(on: night)
        guard myLine.text != mine?.text || myRating.value != Int(mine?.rating ?? 0) else { return }
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
        var items: [UIMenuElement] = [UIAction(title: "Edit details", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.edit() }]
        if Store.shared.share(for: night) != nil {
            items.append(UIAction(title: night.isGuest ? "People and leaving" : "Manage people", image: UIImage(systemName: "person.2")) { [weak self] _ in self?.managePeople() })
        }
        if !night.isGuest {
            items.append(UIAction(title: "Delete night", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() })
        }
        return items
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Delete this night?", message: "It's removed for everyone you invited too.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete night", style: .destructive) { [weak self] _ in
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
        let store = Store.shared
        let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .specifiedRecipientsOnly)
        let provider = NSItemProvider()
        if let share = store.share(for: night) {
            provider.registerCKShare(share, container: store.cloudContainer, allowedSharingOptions: options)
        } else {
            let id = night.objectID
            provider.registerCKShare(container: store.cloudContainer, allowedSharingOptions: options) {
                try await Store.shared.makeShare(for: id)
            }
        }
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

/// One step of the night: a bar that fills as the evening moves on, with its name and when.
private final class StepView: UIStackView {
    enum State { case done, now, todo }

    init(_ step: NightStatus, sub: String, state: State) {
        super.init(frame: .zero)
        let bar = UIView()
        bar.layer.cornerRadius = 3
        bar.backgroundColor = state == .todo ? UIColor(white: 1, alpha: 0.14) : Theme.accent.withAlphaComponent(state == .now ? 1 : 0.55)
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let name = UILabel.make(Theme.label(.caption2, weight: .bold), state == .now ? Theme.accent : state == .done ? Theme.text : Theme.tertiary, lines: 0)
        name.setCaps(step.label, kern: 1)
        let when = UILabel.make(Theme.text(.caption2), Theme.tertiary, lines: 0)
        when.text = sub
        [bar, name, when].forEach(addArrangedSubview)
        axis = .vertical
        spacing = 7
        isAccessibilityElement = true
        accessibilityLabel = "\(step.label), \(sub)" + (state == .now ? ", now" : "")
    }
    required init(coder: NSCoder) { fatalError() }
}

/// A person on a line: initial, name, and something on the right.
private final class PersonRow: UIStackView {
    let name = UILabel.make(Theme.text(.body, weight: .semibold))

    init(_ avatar: Avatar, name text: String, trailing: String?, caption: String? = nil) {
        super.init(frame: .zero)
        name.text = text
        let names = UIStackView(arrangedSubviews: [name])
        names.axis = .vertical
        names.spacing = 2
        if let caption {
            let c = UILabel.make(Theme.text(.caption1), Theme.tertiary)
            c.text = caption
            names.addArrangedSubview(c)
        }
        // A rating reads as a big number; anything else as a small tag.
        let isNumber = trailing.flatMap(Int.init) != nil
        let right = UILabel.make(isNumber ? Theme.display(28, weight: .black) : Theme.label(.caption2, weight: .bold), isNumber ? Theme.accent : Theme.tertiary)
        if isNumber { right.text = trailing } else { right.setCaps(trailing) }
        right.setContentHuggingPriority(.required, for: .horizontal)
        [avatar, names, right].forEach(addArrangedSubview)
        spacing = 12
        alignment = .center
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = .init(top: 10, leading: 0, bottom: 10, trailing: 0)
        isAccessibilityElement = true
        accessibilityLabel = [caption, text, trailing].compactMap { $0 }.joined(separator: ", ")
    }
    required init(coder: NSCoder) { fatalError() }
}

/// The printed ticket: cinema and address with directions, then screen, seats and doors under a perforation.
private final class TicketCard: UIView {
    var onDirections: (() -> Void)?
    private let admit = UILabel.make(Theme.label(.caption2, weight: .bold), UIColor(red: 0.54, green: 0.35, blue: 0.08, alpha: 1))
    private let cinema = UILabel.make(Theme.display(30, weight: .black), .black, lines: 0)
    private let address = UILabel.make(Theme.text(.footnote), UIColor(white: 0.33, alpha: 1), lines: 0)
    private let directions = UIButton(configuration: .filled())
    private let screen = UILabel.make(Theme.display(40, weight: .black), .black)
    private let seats = UILabel.make(Theme.display(40, weight: .black), .black)
    private let doors = UILabel.make(Theme.display(40, weight: .black), .black)
    private let footnote = UILabel.make(Theme.text(.caption1), UIColor(white: 0.33, alpha: 1), lines: 0)
    private let perforation = TicketShape.perforation()
    private let lower = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.957, green: 0.937, blue: 0.894, alpha: 1)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous

        directions.configuration?.title = "Directions"
        directions.configuration?.image = UIImage(systemName: "location.fill")
        directions.configuration?.imagePadding = 6
        directions.configuration?.cornerStyle = .capsule
        directions.configuration?.baseBackgroundColor = .black
        directions.configuration?.baseForegroundColor = .white
        directions.addAction(UIAction { [weak self] _ in self?.onDirections?() }, for: .primaryActionTriggered)
        let directionsRow = UIStackView(arrangedSubviews: [directions, UIView()])

        let upper = UIStackView(arrangedSubviews: [admit, cinema, address, directionsRow])
        upper.axis = .vertical
        upper.spacing = 6
        upper.setCustomSpacing(12, after: address)

        let grid = UIStackView(arrangedSubviews: [Self.cell("Screen", screen), Self.cell("Seats", seats), Self.cell("Doors", doors)])
        grid.distribution = .fillEqually
        grid.spacing = 8
        [grid, footnote].forEach(lower.addArrangedSubview)
        lower.axis = .vertical
        lower.spacing = 12

        let stack = UIStackView(arrangedSubviews: [upper, lower])
        stack.axis = .vertical
        stack.spacing = 36
        addSubview(stack)
        stack.pin(to: self, inset: 18)
        perforation.strokeColor = UIColor(white: 0, alpha: 0.3).cgColor
        layer.addSublayer(perforation)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = lower.convert(CGPoint.zero, to: self).y - 18
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 14, y: y))
        path.addLine(to: CGPoint(x: bounds.width - 14, y: y))
        perforation.path = path.cgPath
    }

    func configure(_ night: MovieNight, admit count: Int) {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight"]
        admit.setCaps("Admit " + (count >= 1 && count <= words.count ? words[count - 1] : "\(count)"))
        cinema.setDisplay((night.cinema ?? "Cinema to be picked").uppercased())
        address.text = night.address
        address.isHidden = night.address == nil
        directions.isHidden = night.cinema == nil
        screen.text = night.screen ?? "–"
        seats.text = night.seats?.uppercased() ?? "–"
        seats.adjustsFontSizeToFitWidth = true
        seats.minimumScaleFactor = 0.5
        let showtime = night.showtime ?? .now
        doors.text = showtime.formatted(date: .omitted, time: .shortened)
        let starts = NightStatus.filmStarts(showtime).formatted(date: .omitted, time: .shortened)
        footnote.text = "Film starts about \(starts) after ads and trailers" + (night.lightsUp.map { " · out by \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
    }

    private static func cell(_ caption: String, _ value: UILabel) -> UIView {
        let label = UILabel.make(Theme.label(.caption2, weight: .bold), UIColor(white: 0.42, alpha: 1))
        label.setCaps(caption)
        let stack = UIStackView(arrangedSubviews: [label, value])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }
}
