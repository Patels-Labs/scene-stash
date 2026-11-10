import UIKit

/// "Your Viewings": every time you've seen a film, newest first, and a button to add one you missed.
final class ViewingsCell: UICollectionViewCell {
    var onAdd: (() -> Void)?
    var onRemove: ((Viewing) -> Void)?
    private let rows = UIStackView()
    private let add = UIButton(configuration: .plain())

    override init(frame: CGRect) {
        super.init(frame: frame)
        Card.style(contentView)
        rows.axis = .vertical
        add.configuration?.title = "Add a Viewing"
        add.configuration?.image = UIImage(systemName: "plus")
        add.configuration?.imagePadding = 8
        add.configuration?.baseForegroundColor = Theme.accent
        add.configuration?.contentInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        add.contentHorizontalAlignment = .leading
        add.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [rows, add])
        stack.axis = .vertical
        contentView.addSubview(stack)
        stack.pin(to: contentView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ viewings: [Viewing]) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, v) in viewings.enumerated().reversed() {
            let date = UILabel.make(Theme.text(.body))
            date.text = v.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            let detail = UILabel.make(Theme.text(.footnote), Theme.secondary)
            detail.text = [i == 0 ? "First time" : nil, v.place].compactMap { $0 }.joined(separator: " · ")
            detail.isHidden = detail.text?.isEmpty ?? true
            let text = UIStackView(arrangedSubviews: [date, detail])
            text.axis = .vertical
            text.spacing = 2
            let row = UIStackView(arrangedSubviews: [text])
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
            row.isAccessibilityElement = true
            row.accessibilityLabel = [date.text, detail.text].compactMap { $0 }.joined(separator: ", ")
            if viewings.count > 1 {
                // Long-press to take one back off, as long as one's left.
                row.addInteraction(UIContextMenuInteraction(delegate: self))
                row.tag = i
                row.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Remove This Viewing") { [weak self] _ in self?.onRemove?(v); return true }]
            }
            rows.addArrangedSubview(row)
            let rule = UIView()
            rule.backgroundColor = Card.rule
            rule.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            rows.addArrangedSubview(rule)
        }
        self.viewings = viewings
    }
    private var viewings: [Viewing] = []
}

extension ViewingsCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let i = interaction.view?.tag, viewings.indices.contains(i) else { return nil }
        let v = viewings[i]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [UIAction(title: "Remove This Viewing", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self?.onRemove?(v) }])
        })
    }
}

/// Add a Viewing: the day you saw it and, if you like, where.
final class ViewingFormViewController: UIViewController {
    private let picker = UIDatePicker()
    private let place = UITextField()
    private let done: (Date, String?) -> Void

    init(done: @escaping (Date, String?) -> Void) {
        self.done = done
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add a Viewing"
        installBackdrop()
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            done(picker.date, place.text?.trimmingCharacters(in: .whitespaces))
            Haptics.success()
            dismiss(animated: true)
        })
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.maximumDate = .now
        picker.tintColor = Theme.accent
        place.attributedPlaceholder = NSAttributedString(string: "Where (optional)", attributes: [.foregroundColor: Theme.tertiary])
        place.font = Theme.text(.body)
        place.textColor = Theme.text
        Card.style(place)
        place.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        place.leftViewMode = .always
        place.returnKeyType = .done
        place.heightAnchor.constraint(equalToConstant: 50).isActive = true
        place.addAction(UIAction { [weak self] _ in self?.place.resignFirstResponder() }, for: .editingDidEndOnExit)
        let stack = UIStackView(arrangedSubviews: [picker, place])
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Shelf.margin),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
        ])
    }
}
