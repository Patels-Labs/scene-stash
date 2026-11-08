import MapKit
import UIKit

/// Step one of planning a night: which film. Your watchlist first, or search for anything.
final class NightFilmPickerViewController: UITableViewController, UISearchResultsUpdating {
    private let onSave: (MovieNight) -> Void
    private let shortlist = Store.shared.all().filter { $0.mediaType == .movie && $0.status != .seen }.map(\.title)
    private var results: [Title] = []
    private var search: Task<Void, Never>?
    private var searching: Bool { navigationItem.searchController?.searchBar.text?.isEmpty == false }

    init(onSave: @escaping (MovieNight) -> Void) {
        self.onSave = onSave
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Which film?"
        tableView.backgroundColor = Theme.bg
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let searchController = UISearchController()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search films"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    func updateSearchResults(for searchController: UISearchController) {
        search?.cancel()
        let text = searchController.searchBar.text ?? ""
        search = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = text.isEmpty ? [] : ((try? await TMDB.shared.search(text)) ?? []).filter { $0.mediaType == .movie }
            tableView.reloadData()
        }
    }

    private var rows: [Title] { searching ? results : shortlist }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        searching ? nil : shortlist.isEmpty ? "Search for a film" : "From your library"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let title = rows[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = title.name
        config.secondaryText = title.year
        config.secondaryTextProperties.color = Theme.secondary
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(NightFormViewController(title: rows[indexPath.row], onSave: onSave), animated: true)
    }
}

/// The ticket details: when, where, screen and seats, and whether anyone's booked yet.
final class NightFormViewController: UIViewController, MKLocalSearchCompleterDelegate {
    private let film: Title
    private let night: MovieNight?
    private let onSave: (MovieNight) -> Void
    private var runtime: Int?

    private let when = UIDatePicker()
    private let cinema = NightFormViewController.textField("Odeon Luxe Leicester Square")
    private let address = NightFormViewController.textField("Street or postcode, for directions")
    private let screen = NightFormViewController.textField("1")
    private let seats = NightFormViewController.textField("H7–H10")
    private let booked = UISwitch()
    /// Cinemas matching what's typed in Cinema; picking one fills in its address too.
    private let completer = MKLocalSearchCompleter()
    private let suggestions = UIStackView()

    init(title: Title, onSave: @escaping (MovieNight) -> Void) {
        film = title
        night = nil
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    init(night: MovieNight) {
        film = night.title
        self.night = night
        onSave = { _ in }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        title = night == nil ? "Plan a night" : "Edit night"
        navigationItem.largeTitleDisplayMode = .never
        if night != nil || navigationController?.viewControllers.first == self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self] _ in self?.save() })

        when.datePickerMode = .dateAndTime
        when.preferredDatePickerStyle = .compact
        when.minuteInterval = 5
        when.date = night?.showtime ?? Self.defaultShowtime()
        cinema.text = night?.cinema
        cinema.textContentType = .organizationName
        address.text = night?.address
        address.textContentType = .fullStreetAddress
        screen.text = night?.screen
        seats.text = night?.seats
        booked.isOn = night?.booked ?? false
        booked.onTintColor = Theme.accent

        // Return goes to the next field; the last one closes the keyboard.
        let fields = [cinema, address, screen, seats]
        for (i, field) in fields.enumerated() {
            let next = fields.indices.contains(i + 1) ? fields[i + 1] : nil
            field.returnKeyType = next == nil ? .done : .next
            field.addAction(UIAction { [weak field, weak next] _ in
                if let next { next.becomeFirstResponder() } else { field?.resignFirstResponder() }
            }, for: .editingDidEndOnExit)
        }
        // So does tapping anywhere that isn't a field.
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        completer.delegate = self
        completer.resultTypes = .pointOfInterest
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        cinema.addAction(UIAction { [weak self] _ in self?.searchCinemas() }, for: .editingChanged)
        for field in [address, screen, seats] {
            field.addAction(UIAction { [weak self] _ in self?.showSuggestions([]) }, for: .editingDidBegin)
        }
        suggestions.axis = .vertical
        suggestions.backgroundColor = Theme.surface
        suggestions.layer.cornerRadius = 12
        suggestions.clipsToBounds = true
        suggestions.isHidden = true

        let filmLabel = UILabel.make(Theme.text(.title1, weight: .bold), Theme.text, lines: 0)
        filmLabel.text = film.name
        let whenRow = UIStackView(arrangedSubviews: [UILabel.make(Theme.text(.body)), when])
        (whenRow.arrangedSubviews[0] as? UILabel)?.text = "Showtime"
        let bookedLabel = UILabel.make(Theme.text(.body), Theme.text, lines: 0)
        bookedLabel.text = "We've got tickets"
        let bookedRow = UIStackView(arrangedSubviews: [bookedLabel, booked])
        let screenSeats = UIStackView(arrangedSubviews: [Self.field("Screen", screen), Self.field("Seats", seats)])
        screenSeats.distribution = .fillEqually
        screenSeats.spacing = 12

        let stack = UIStackView(arrangedSubviews: [
            filmLabel, Self.card(whenRow), Self.field("Cinema", cinema), suggestions, Self.field("Address", address), screenSeats, Self.card(bookedRow),
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.setCustomSpacing(26, after: filmLabel)
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.pin(to: view)
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        if night == nil || night?.runtime == 0 {
            Task { runtime = try? await TMDB.shared.detail(film.id, .movie).runtime }
        }
    }

    // MARK: Cinema search

    private func searchCinemas() {
        let text = cinema.text?.trimmingCharacters(in: .whitespaces) ?? ""
        if text.count < 2 { showSuggestions([]); return }
        completer.queryFragment = text
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        showSuggestions(cinema.isFirstResponder ? Array(completer.results.prefix(4)) : [])
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        showSuggestions([])
    }

    private func showSuggestions(_ results: [MKLocalSearchCompletion]) {
        suggestions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for result in results {
            var config = UIButton.Configuration.plain()
            config.title = result.title
            config.subtitle = result.subtitle.isEmpty ? nil : result.subtitle
            config.image = UIImage(systemName: "popcorn")
            config.imagePadding = 12
            config.titleAlignment = .leading
            config.baseForegroundColor = Theme.text
            config.contentInsets = .init(top: 12, leading: 14, bottom: 12, trailing: 14)
            config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a; a.foregroundColor = Theme.secondary; return a
            }
            let button = UIButton(configuration: config)
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in self?.pick(result) }, for: .primaryActionTriggered)
            suggestions.addArrangedSubview(button)
        }
        guard suggestions.isHidden != results.isEmpty else { return }
        UIView.animate(withDuration: 0.2) { self.suggestions.isHidden = results.isEmpty }
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        Haptics.tap()
        cinema.text = result.title
        if !result.subtitle.isEmpty { address.text = result.subtitle }
        showSuggestions([])
        screen.becomeFirstResponder()
    }

    private func save() {
        let night = night ?? Store.shared.newNight(for: film, runtime: runtime)
        night.showtime = when.date
        night.cinema = Self.clean(cinema.text)
        night.address = Self.clean(address.text)
        night.screen = Self.clean(screen.text)
        night.seats = Self.clean(seats.text)
        if booked.isOn, !night.booked { night.bookedBy = Store.shared.myName(on: night) }
        if !booked.isOn { night.bookedBy = nil }
        night.booked = booked.isOn
        if night.runtime == 0, let runtime { night.runtime = Int32(runtime) }
        Store.shared.save()
        Haptics.success()
        let onSave = onSave
        dismiss(animated: true) { onSave(night) }
    }

    /// Tonight at 19:30, or tomorrow if that's gone.
    private static func defaultShowtime(now: Date = .now) -> Date {
        let cal = Calendar.current
        let tonight = cal.date(bySettingHour: 19, minute: 30, second: 0, of: now) ?? now
        return tonight > now ? tonight : cal.date(byAdding: .day, value: 1, to: tonight) ?? tonight
    }

    private static func clean(_ text: String?) -> String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return t?.isEmpty == false ? t : nil
    }

    private static func textField(_ placeholder: String) -> UITextField {
        let f = UITextField()
        f.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: Theme.tertiary])
        f.font = Theme.text(.body)
        f.textColor = Theme.text
        f.adjustsFontForContentSizeCategory = true
        f.clearButtonMode = .whileEditing
        f.backgroundColor = Theme.surface
        f.layer.cornerRadius = 12
        f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        f.leftViewMode = .always
        f.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return f
    }

    private static func field(_ caption: String, _ input: UIView) -> UIView {
        let label = UILabel.make(Theme.label(), Theme.tertiary)
        label.setCaps(caption)
        input.accessibilityLabel = caption
        let stack = UIStackView(arrangedSubviews: [label, input])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private static func card(_ row: UIStackView) -> UIView {
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 10, leading: 14, bottom: 10, trailing: 14)
        row.backgroundColor = Theme.surface
        row.layer.cornerRadius = 12
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        return row
    }
}
