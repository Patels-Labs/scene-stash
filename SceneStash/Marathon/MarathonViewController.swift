import UIKit

/// Your saved marathons.
final class MarathonListViewController: UITableViewController {
    private var marathons: [Marathon] = []

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Marathons"
        tableView.backgroundColor = Theme.bg
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "m")
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSManagedObjectContextObjectsDidChange, object: Store.shared.context)
        reload()
    }

    @objc private func reload() {
        marathons = Store.shared.marathons()
        let empty = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)
        empty.text = "No marathons yet. Open any film in a series, or a show, and tap Plan a Marathon."
        empty.textAlignment = .center
        tableView.backgroundView = marathons.isEmpty ? empty : nil
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { marathons.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "m", for: indexPath)
        let m = marathons[indexPath.row]
        let left = m.remaining
        let next = m.upcomingPlan().first { !$0.slots.isEmpty }?.slots.first?.start
        let when = next.map { "Next " + $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) } ?? "Needs a date"
        let row = MarathonRow(art: left.first?.backdrop ?? m.pieces.first?.backdrop, title: m.name ?? "Marathon",
                              first: left.isEmpty ? "All watched" : "\(left.count) to go", second: left.isEmpty ? nil : when)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.contentView.addSubview(row)
        row.pin(to: cell.contentView, inset: 12)
        cell.backgroundColor = Card.fill
        cell.accessoryType = .disclosureIndicator
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = row.accessibilityLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(MarathonPlannerViewController(marathon: marathons[indexPath.row]), animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        Store.shared.context.delete(marathons[indexPath.row])
        Store.shared.save()
    }
}

/// Plan a marathon: the days (start and end for each), the break between pieces, whether the last one
/// may run over, and the resulting plan, recalculated as you change any of it.
final class MarathonPlannerViewController: UIViewController {
    private var marathon: Marathon?
    private let name: String
    private let pieces: [Piece]
    private var days: [MarathonDay]
    private var breakMinutes: Int
    private var runOver: Bool

    private let dayRows = UIStackView()
    private let breakLabel = UILabel.make(Theme.text(.body, weight: .semibold).monospacedDigits)
    private let planStack = UIStackView()
    private let save = CapsuleButton.primary("Add to Tonight")

    /// A new marathon from a set of pieces.
    init(name: String, pieces: [Piece]) {
        self.name = name
        self.pieces = pieces
        breakMinutes = pieces.first?.isEpisode == true ? 5 : 20
        runOver = true
        days = []
        super.init(nibName: nil, bundle: nil)
        days = defaultDays()
    }

    /// Editing a saved one.
    init(marathon: Marathon) {
        self.marathon = marathon
        name = marathon.name ?? "Marathon"
        pieces = marathon.remaining
        days = marathon.days.filter { $0.end > .now }
        breakMinutes = Int(marathon.breakMinutes)
        runOver = marathon.runOver
        super.init(nibName: nil, bundle: nil)
        if days.isEmpty { days = defaultDays() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var noun: String { pieces.first?.isEpisode == true ? "episode" : "film" }

    /// Tonight from 19:30 (or now, if later) to 23:30, adding the same evening on following days until everything fits.
    private func defaultDays() -> [MarathonDay] {
        let cal = Calendar.current
        var result: [MarathonDay] = []
        var day = cal.startOfDay(for: .now)
        while result.count < 14 {
            let doors = cal.date(bySettingHour: 19, minute: 30, second: 0, of: day)!
            let lights = cal.date(bySettingHour: 23, minute: 30, second: 0, of: day)!
            if lights > .now { result.append(MarathonDay(start: max(doors, Self.roundUp(.now)), end: lights)) }
            if MarathonPlan.plan(pieces, days: result, breakMinutes: breakMinutes, runOver: runOver).left.isEmpty { break }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private static func roundUp(_ date: Date) -> Date {
        let quarter: TimeInterval = 15 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installBackdrop()
        navigationItem.largeTitleDisplayMode = .never
        if marathon != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .trash, primaryAction: UIAction { [weak self] _ in self?.delete() })
        }
        let scroll = UIScrollView()
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 8, leading: Shelf.margin, bottom: 120, trailing: Shelf.margin)

        let art = ArtView(radius: 12)
        art.show(TMDB.imageURL(pieces.first?.backdrop, .backdrop), name: nil)
        art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 9.0 / 16).isActive = true
        let heading = UILabel.make(Theme.text(.title1, weight: .bold), Theme.text, lines: 0)
        heading.text = name
        heading.accessibilityTraits = .header
        let meta = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)
        let total = pieces.reduce(0) { $0 + $1.minutes }
        meta.text = "\(pieces.count) \(noun)\(pieces.count == 1 ? "" : "s") · \(DateText.runtime(total))"
        let schedule = scheduleCard()
        planStack.axis = .vertical
        planStack.spacing = Shelf.gap
        [art, heading, meta, Self.heading("Schedule"), schedule, planStack].forEach(content.addArrangedSubview)
        content.setCustomSpacing(4, after: heading)
        content.setCustomSpacing(28, after: meta)
        content.setCustomSpacing(32, after: schedule)

        scroll.addSubview(content)
        view.addSubview(scroll)
        scroll.pin(to: view)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        save.configuration?.title = marathon == nil ? "Add to Tonight" : "Save Changes"
        save.addAction(UIAction { [weak self] _ in self?.commit() }, for: .primaryActionTriggered)
        view.addSubview(save)
        save.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            save.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Shelf.margin),
            save.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
            save.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        rebuildDays()
        replan()
    }

    // MARK: Schedule

    private static func heading(_ text: String) -> UILabel {
        let label = UILabel.make(Theme.text(.title2, weight: .semibold))
        label.text = text
        label.accessibilityTraits = .header
        return label
    }

    private func scheduleCard() -> UIView {
        let card = UIStackView()
        Card.style(card)
        card.axis = .vertical
        card.spacing = 14
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        dayRows.axis = .vertical
        dayRows.spacing = 14
        let add = CapsuleButton.glass("Add a Day", image: "plus")
        add.addAction(UIAction { [weak self] _ in self?.addDay() }, for: .primaryActionTriggered)

        let stepper = UIStepper()
        stepper.maximumValue = 90
        stepper.stepValue = 5
        stepper.value = Double(breakMinutes)
        stepper.accessibilityLabel = "Break length"
        stepper.addAction(UIAction { [weak self, weak stepper] _ in
            self?.breakMinutes = Int(stepper?.value ?? 0)
            self?.replan()
        }, for: .valueChanged)
        let length = UIStackView(arrangedSubviews: [breakLabel, stepper])
        length.alignment = .center
        length.spacing = 8
        let breakRow = Self.row(title: "Break between \(noun)s", detail: noun == "film" ? "Snacks, stretch, pee." : "Just long enough for the next one to load.", trailing: length)

        let toggle = UISwitch()
        toggle.isOn = runOver
        toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.runOver = toggle?.isOn ?? true; self?.replan() }, for: .valueChanged)
        let overRow = Self.row(title: "Let the last one run over", detail: "If the end time lands mid-\(noun), finish it (up to an hour late) instead of moving it to the next day.", trailing: toggle)

        let rule = UIView()
        rule.backgroundColor = Card.rule
        rule.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        [dayRows, add, rule, breakRow, overRow].forEach(card.addArrangedSubview)
        return card
    }

    private static func row(title: String, detail: String? = nil, trailing: UIView) -> UIView {
        let t = UILabel.make(Theme.text(.body), Theme.text, lines: 0)
        t.text = title
        let d = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
        d.text = detail
        d.isHidden = detail == nil
        let text = UIStackView(arrangedSubviews: [t, d])
        text.axis = .vertical
        text.spacing = 2
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [text, trailing])
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private static func picker(_ mode: UIDatePicker.Mode, _ date: Date, label: String) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = mode
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        picker.date = date
        picker.accessibilityLabel = label
        return picker
    }

    private func rebuildDays() {
        dayRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, day) in days.enumerated() {
            let start = Self.picker(.dateAndTime, day.start, label: "Day \(i + 1) start")
            let end = Self.picker(.time, day.end, label: "Day \(i + 1) end")
            start.addAction(UIAction { [weak self, weak start, weak end] _ in self?.edit(i, start: start?.date, end: end?.date) }, for: .valueChanged)
            end.addAction(UIAction { [weak self, weak start, weak end] _ in self?.edit(i, start: start?.date, end: end?.date) }, for: .valueChanged)
            let block = UIStackView(arrangedSubviews: [Self.row(title: "Starts", trailing: start), Self.row(title: "Ends", trailing: end)])
            block.axis = .vertical
            block.spacing = 8
            if days.count > 1 {
                let remove = CapsuleButton.circle("minus", label: "Remove day \(i + 1)")
                remove.addAction(UIAction { [weak self] _ in self?.removeDay(i) }, for: .primaryActionTriggered)
                block.insertArrangedSubview(Self.row(title: "Day \(i + 1)", trailing: remove), at: 0)
            }
            dayRows.addArrangedSubview(block)
        }
    }

    /// The end is a time on the start's day; anything at or before the start means after midnight.
    private func edit(_ i: Int, start: Date?, end: Date?) {
        guard let start, let end, days.indices.contains(i) else { return }
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: end)
        var lights = cal.date(bySettingHour: parts.hour ?? 23, minute: parts.minute ?? 30, second: 0, of: start) ?? end
        if lights <= start { lights = cal.date(byAdding: .day, value: 1, to: lights) ?? lights }
        days[i] = MarathonDay(start: start, end: lights)
        days.sort { $0.start < $1.start }
        replan()
    }

    private func addDay() {
        let cal = Calendar.current
        let last = days.last ?? MarathonDay(start: .now, end: .now.addingTimeInterval(4 * 3600))
        let next = MarathonDay(start: cal.date(byAdding: .day, value: 1, to: last.start)!, end: cal.date(byAdding: .day, value: 1, to: last.end)!)
        days.append(next)
        Haptics.tap()
        rebuildDays()
        replan()
    }

    private func removeDay(_ i: Int) {
        days.remove(at: i)
        Haptics.tap()
        rebuildDays()
        replan()
    }

    // MARK: Plan

    private func replan() {
        breakLabel.text = "\(breakMinutes) min"
        planStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let plan = MarathonPlan.plan(pieces, days: days, breakMinutes: breakMinutes, runOver: runOver)
        for (day, slots) in zip(days, plan.days) {
            let note = UILabel.make(Theme.text(.footnote), Theme.secondary)
            let lastEnd = slots.last?.end ?? day.start
            if let over = slots.last, over.overruns {
                note.text = "Runs \(Int(over.end.timeIntervalSince(day.end) / 60)) min over"
                note.textColor = Theme.accent
            } else {
                note.text = slots.isEmpty ? "Nothing fits" : "\(DateText.runtime(Int(day.end.timeIntervalSince(lastEnd) / 60))) spare"
            }
            let head = UIStackView(arrangedSubviews: [Self.heading(day.start.formatted(.dateTime.weekday(.wide))), UIView(), note])
            head.alignment = .lastBaseline
            planStack.addArrangedSubview(head)
            planStack.setCustomSpacing(12, after: head)
            for (i, slot) in slots.enumerated() {
                planStack.addArrangedSubview(Self.slotRow(slot))
                if i < slots.count - 1, breakMinutes > 0 {
                    planStack.addArrangedSubview(Self.timeLine(slot.end, "Break · \(breakMinutes) min"))
                }
            }
            let finish = Self.timeLine(lastEnd, "Finishes · Planned " + day.end.formatted(.dateTime.hour().minute()))
            planStack.addArrangedSubview(finish)
            planStack.setCustomSpacing(32, after: finish)
        }
        if !plan.left.isEmpty {
            let warn = UILabel.make(Theme.text(.subheadline, weight: .semibold), Theme.accent, lines: 0)
            warn.text = "\(plan.left.count) \(noun)\(plan.left.count == 1 ? " doesn't" : "s don't") fit yet. Add a day or end later."
            planStack.addArrangedSubview(warn)
        }
    }

    private static func slotRow(_ slot: PlannedSlot) -> UIView {
        let piece = slot.piece
        var bits = [DateText.runtime(piece.minutes)]
        if piece.isEpisode, let s = piece.season, let e = piece.episode { bits.insert("S\(s) · E\(e)", at: 0) }
        if slot.overruns { bits.append("Runs over") }
        return MarathonRow(art: piece.backdrop ?? piece.poster, title: piece.isEpisode ? (piece.detail ?? "Episode \(piece.episode ?? 0)") : piece.name,
                           first: slot.start.formatted(.dateTime.hour().minute()), second: bits.joined(separator: " · "), tint: slot.overruns ? Theme.accent : nil)
    }

    private static func timeLine(_ time: Date, _ text: String) -> UILabel {
        let label = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
        label.text = time.formatted(.dateTime.hour().minute()) + " · " + text
        return label
    }

    private func commit() {
        Haptics.success()
        if let marathon {
            marathon.days = days
            marathon.breakMinutes = Int16(breakMinutes)
            marathon.runOver = runOver
            Store.shared.save()
        } else {
            _ = Store.shared.newMarathon(name: name, pieces: pieces, days: days, breakMinutes: breakMinutes, runOver: runOver)
        }
        navigationController?.popViewController(animated: true)
    }

    private func delete() {
        guard let marathon else { return }
        Store.shared.context.delete(marathon)
        Store.shared.save()
        navigationController?.popViewController(animated: true)
    }
}

/// Wide art with a title and two quieter lines beside it: a saved marathon, or a piece in the plan.
private final class MarathonRow: UIStackView {
    init(art path: String?, title: String, first: String?, second: String?, tint: UIColor? = nil) {
        super.init(frame: .zero)
        let art = ArtView(radius: 12)
        art.show(TMDB.imageURL(path, .hero), name: nil)
        art.widthAnchor.constraint(equalToConstant: 120).isActive = true
        art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 9.0 / 16).isActive = true
        let name = UILabel.make(Theme.text(.headline, weight: .semibold), Theme.text, lines: 2)
        name.text = title
        let captions = CaptionStack()
        captions.set(first, second, tint: tint)
        captions.second.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [name, captions])
        text.axis = .vertical
        text.spacing = 3
        [art, text].forEach(addArrangedSubview)
        alignment = .center
        spacing = 12
        isAccessibilityElement = true
        accessibilityLabel = [first, title, second].compactMap { $0 }.joined(separator: ", ")
    }
    required init(coder: NSCoder) { fatalError() }
}
