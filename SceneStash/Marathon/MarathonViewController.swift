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
        empty.text = "No marathons yet. Open any film in a series, or a show, and tap Plan a marathon."
        empty.textAlignment = .center
        tableView.backgroundView = marathons.isEmpty ? empty : nil
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { marathons.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "m", for: indexPath)
        let m = marathons[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = m.name
        config.textProperties.font = Theme.display(24, weight: .black)
        let left = m.remaining.count
        let next = m.upcomingPlan().first { !$0.slots.isEmpty }?.slots.first?.start
        config.secondaryText = left == 0 ? "All watched" : "\(left) to go" + (next.map { " · next " + $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) } ?? " · needs a date")
        config.secondaryTextProperties.color = Theme.secondary
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
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

/// Plan a marathon: the days (doors and lights up for each), the break between pieces, whether the last one
/// may run over, and the resulting programme, recalculated as you change any of it.
final class MarathonPlannerViewController: UIViewController {
    private var marathon: Marathon?
    private let name: String
    private let pieces: [Piece]
    private var days: [MarathonDay]
    private var breakMinutes: Int
    private var runOver: Bool

    private let dayRows = UIStackView()
    private let breakLabel = UILabel.make(Theme.display(24, weight: .black))
    private let planStack = UIStackView()
    private let save = PillButton("Put it on the programme")

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
        content.spacing = 14
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 8, leading: 16, bottom: 120, trailing: 16)

        let kicker = UILabel.make(Theme.label(), Theme.secondary)
        let total = pieces.reduce(0) { $0 + $1.minutes }
        kicker.setCaps("Marathon · \(pieces.count) \(noun)\(pieces.count == 1 ? "" : "s") · \(DateText.runtime(total))")
        let title = UILabel.make(Theme.display(56, weight: .black), Theme.text, lines: 0)
        title.setDisplay(name.uppercased())
        title.accessibilityTraits = .header
        [kicker, title, scheduleCard()].forEach(content.addArrangedSubview)
        content.setCustomSpacing(24, after: title)
        planStack.axis = .vertical
        planStack.spacing = 6
        content.addArrangedSubview(planStack)
        content.setCustomSpacing(30, after: content.arrangedSubviews[2])

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
        save.configuration?.title = marathon == nil ? "Put it on the programme" : "Save changes"
        save.addAction(UIAction { [weak self] _ in self?.commit() }, for: .primaryActionTriggered)
        view.addSubview(save)
        save.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            save.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            save.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            save.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        rebuildDays()
        replan()
    }

    // MARK: Schedule

    private func scheduleCard() -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 14
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        card.backgroundColor = UIColor(white: 1, alpha: 0.06)
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        let caption = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.accent)
        caption.setCaps("The schedule")
        dayRows.axis = .vertical
        dayRows.spacing = 10
        let add = UIButton(type: .system)
        add.setTitle("+ Add a day", for: .normal)
        add.titleLabel?.font = Theme.text(.subheadline, weight: .bold)
        add.tintColor = Theme.secondary
        add.addAction(UIAction { [weak self] _ in self?.addDay() }, for: .primaryActionTriggered)

        let minus = Self.round("minus") { [weak self] in self?.nudgeBreak(-5) }
        let plus = Self.round("plus") { [weak self] in self?.nudgeBreak(5) }
        breakLabel.textAlignment = .center
        breakLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let stepper = UIStackView(arrangedSubviews: [minus, breakLabel, plus])
        stepper.alignment = .center
        stepper.spacing = 6
        let breakRow = Self.row(title: "Break between \(noun)s", detail: noun == "film" ? "Snacks, stretch, pee." : "Just long enough for the next one to load.", trailing: stepper)

        let toggle = UISwitch()
        toggle.isOn = runOver
        toggle.onTintColor = Theme.accent
        toggle.addAction(UIAction { [weak self, weak toggle] _ in self?.runOver = toggle?.isOn ?? true; self?.replan() }, for: .valueChanged)
        let overRow = Self.row(title: "Let the last one run over", detail: "If lights up lands mid-\(noun), finish it (up to an hour late) instead of moving it to the next day.", trailing: toggle)

        let rule = UIView()
        rule.backgroundColor = Theme.hairline
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        [caption, dayRows, add, rule, breakRow, overRow].forEach(card.addArrangedSubview)
        return card
    }

    private static func round(_ symbol: String, _ action: @escaping () -> Void) -> UIButton {
        let b = UIButton(configuration: .gray())
        b.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        b.configuration?.cornerStyle = .capsule
        b.accessibilityLabel = symbol == "plus" ? "Longer break" : "Shorter break"
        b.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }

    private static func row(title: String, detail: String, trailing: UIView) -> UIView {
        let t = UILabel.make(Theme.text(.subheadline, weight: .bold), Theme.text, lines: 0)
        t.text = title
        let d = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
        d.text = detail
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

    private func rebuildDays() {
        dayRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, day) in days.enumerated() {
            let start = UIDatePicker()
            start.datePickerMode = .dateAndTime
            start.preferredDatePickerStyle = .compact
            start.minuteInterval = 5
            start.date = day.start
            start.tintColor = Theme.accent
            start.accessibilityLabel = "Day \(i + 1) doors"
            let end = UIDatePicker()
            end.datePickerMode = .time
            end.preferredDatePickerStyle = .compact
            end.minuteInterval = 5
            end.date = day.end
            end.tintColor = Theme.accent
            end.accessibilityLabel = "Day \(i + 1) lights up"
            start.addAction(UIAction { [weak self, weak start, weak end] _ in self?.edit(i, start: start?.date, end: end?.date) }, for: .valueChanged)
            end.addAction(UIAction { [weak self, weak start, weak end] _ in self?.edit(i, start: start?.date, end: end?.date) }, for: .valueChanged)
            let to = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.tertiary)
            to.setCaps("to")
            let row = UIStackView(arrangedSubviews: [start, to, end, UIView()])
            row.alignment = .center
            row.spacing = 8
            if days.count > 1 {
                let remove = UIButton(type: .system)
                remove.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
                remove.tintColor = Theme.tertiary
                remove.accessibilityLabel = "Remove day \(i + 1)"
                remove.addAction(UIAction { [weak self] _ in self?.removeDay(i) }, for: .primaryActionTriggered)
                row.addArrangedSubview(remove)
            }
            dayRows.addArrangedSubview(row)
        }
    }

    /// Lights up is a time on the doors' day; anything at or before doors means after midnight.
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

    private func nudgeBreak(_ by: Int) {
        breakMinutes = min(max(breakMinutes + by, 0), 90)
        Haptics.tap()
        replan()
    }

    // MARK: Plan

    private func replan() {
        breakLabel.text = "\(breakMinutes)M"
        planStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let plan = MarathonPlan.plan(pieces, days: days, breakMinutes: breakMinutes, runOver: runOver)
        for (day, slots) in zip(days, plan.days) {
            let heading = UILabel.make(Theme.display(30, weight: .black))
            heading.text = day.start.formatted(.dateTime.weekday(.wide)).uppercased()
            let note = UILabel.make(Theme.label(), Theme.secondary)
            let lastEnd = slots.last?.end ?? day.start
            if let over = slots.last, over.overruns {
                note.setCaps("Runs \(Int(over.end.timeIntervalSince(day.end) / 60)) min over")
                note.textColor = Theme.accent
            } else {
                note.setCaps(slots.isEmpty ? "Nothing fits" : "\(DateText.runtime(Int(day.end.timeIntervalSince(lastEnd) / 60))) spare")
            }
            let head = UIStackView(arrangedSubviews: [heading, UIView(), note])
            head.alignment = .lastBaseline
            planStack.addArrangedSubview(head)
            planStack.setCustomSpacing(10, after: head)
            for (i, slot) in slots.enumerated() {
                planStack.addArrangedSubview(MarathonSlotRow(time: slot.start, piece: slot.piece, overruns: slot.overruns))
                if i < slots.count - 1, breakMinutes > 0 {
                    planStack.addArrangedSubview(MarathonSlotRow(time: slot.end, breakMinutes: breakMinutes))
                }
            }
            let lights = MarathonSlotRow(time: lastEnd, lightsUp: "Planned " + day.end.formatted(.dateTime.hour().minute()))
            planStack.addArrangedSubview(lights)
            planStack.setCustomSpacing(26, after: lights)
        }
        if !plan.left.isEmpty {
            let warn = UILabel.make(Theme.text(.subheadline, weight: .semibold), Theme.accent, lines: 0)
            warn.text = "\(plan.left.count) \(noun)\(plan.left.count == 1 ? " doesn't" : "s don't") fit yet. Add a day or stretch lights up."
            planStack.addArrangedSubview(warn)
        }
    }

    private func commit() {
        Haptics.success()
        if let marathon {
            marathon.days = days
            marathon.breakMinutes = Int16(breakMinutes)
            marathon.runOver = runOver
            Store.shared.save()
            navigationController?.popViewController(animated: true)
        } else {
            _ = Store.shared.newMarathon(name: name, pieces: pieces, days: days, breakMinutes: breakMinutes, runOver: runOver)
            navigationController?.popViewController(animated: true)
        }
    }

    private func delete() {
        guard let marathon else { return }
        Store.shared.context.delete(marathon)
        Store.shared.save()
        navigationController?.popViewController(animated: true)
    }
}

/// A line of the marathon plan: the time in the gutter and a piece, a break, or lights up.
private final class MarathonSlotRow: UIStackView {
    private let card = UIView()

    private init(time: Date) {
        super.init(frame: .zero)
        let label = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.tertiary)
        label.setCaps(time.formatted(.dateTime.hour().minute()), kern: 1)
        label.widthAnchor.constraint(equalToConstant: 50).isActive = true
        alignment = .top
        spacing = 6
        addArrangedSubview(label)
        addArrangedSubview(card)
    }
    required init(coder: NSCoder) { fatalError() }

    convenience init(time: Date, piece: Piece, overruns: Bool) {
        self.init(time: time)
        card.backgroundColor = Theme.surfaceHigh
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        if overruns { card.layer.borderWidth = 2; card.layer.borderColor = Theme.accent.cgColor }
        let name = UILabel.make(Theme.display(22, weight: .black), Theme.text, lines: 2)
        name.text = (piece.isEpisode ? (piece.detail ?? "Episode \(piece.episode ?? 0)") : piece.name).uppercased()
        let meta = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)
        var bits = [DateText.runtime(piece.minutes)]
        if piece.isEpisode, let s = piece.season, let e = piece.episode { bits.insert("S\(s) · E\(e)", at: 0) }
        if overruns { bits.append("runs over") }
        meta.setCaps(bits.joined(separator: " · "), kern: 1)
        let stack = UIStackView(arrangedSubviews: [meta, name])
        stack.axis = .vertical
        stack.spacing = 4
        card.addSubview(stack)
        stack.pin(to: card, inset: 12)
        // Taller for longer pieces, so the day reads like a timeline.
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: min(max(CGFloat(piece.minutes) * 0.42, 54), 90)).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = "\(time.formatted(date: .omitted, time: .shortened)), \(name.text?.capitalized ?? ""), \(bits.joined(separator: ", "))"
    }

    convenience init(time: Date, breakMinutes: Int) {
        self.init(time: time)
        let label = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.secondary)
        label.setCaps("Break · \(breakMinutes) min", kern: 1)
        card.addSubview(label)
        label.pin(to: card, inset: 8)
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        isAccessibilityElement = true
        accessibilityLabel = "Break, \(breakMinutes) minutes"
    }

    convenience init(time: Date, lightsUp note: String) {
        self.init(time: time)
        let label = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.tertiary)
        label.setCaps("Lights up · \(note)", kern: 1)
        card.addSubview(label)
        label.pin(to: card, inset: 0)
        isAccessibilityElement = true
        accessibilityLabel = "Lights up, \(note)"
    }
}
