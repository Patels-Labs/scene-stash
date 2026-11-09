import UIKit

/// The All-Access Pass: posters, what it adds, and one button.
final class PaywallViewController: UIViewController {
    private let posters = (0..<3).map { _ in ArtView(radius: 10) }
    private let posterRow = UIStackView()
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let primary = CapsuleButton.primary("Start free trial")
    private var busy = false { didSet { primary.isEnabled = !busy; primary.configuration?.showsActivityIndicator = busy } }

    private static let benefits: [(String, String, String)] = [
        ("sparkles", "Year in Review", "A year-end reel of everything you watched, ready to share."),
        ("play.circle", "Live Activity and Widgets", "A Live Activity with time left and when it ends, plus Tonight on your Home Screen."),
        ("calendar", "Marathons", "Plan a whole franchise or season across nights, with breaks."),
        ("clock.arrow.circlepath", "History", "Every film you finish is kept with its date, your rating and a note."),
        ("bell.badge", "Premiere Alerts and Icons", "A nudge the night a new episode lands, and a set of alternate app icons."),
    ]

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg

        let close = CapsuleButton.circle("xmark", label: "Close")
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        let restore = Self.plainButton("Restore", Theme.text) { [weak self] in self?.restore() }

        posterRow.spacing = Shelf.gap
        posterRow.distribution = .fillEqually
        posters.forEach {
            posterRow.addArrangedSubview($0)
            $0.heightAnchor.constraint(equalTo: $0.widthAnchor, multiplier: 1.5).isActive = true
        }
        let headline = UILabel.make(Theme.text(.largeTitle, weight: .bold), Theme.text, lines: 0)
        headline.text = "All-Access Pass"
        headline.accessibilityTraits = .header
        let body = UILabel.make(Theme.text(.body), Theme.secondary, lines: 0)
        body.text = "Tracking stays free. The pass adds the extras, for one small price a year."

        let content = UIStackView(arrangedSubviews: [posterRow, headline, body])
        content.axis = .vertical
        content.spacing = 20
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 8, leading: Shelf.margin, bottom: 24, trailing: Shelf.margin)
        content.setCustomSpacing(28, after: posterRow)
        content.setCustomSpacing(8, after: headline)
        content.setCustomSpacing(28, after: body)
        Self.benefits.forEach { content.addArrangedSubview(Self.benefit($0.0, $0.1, $0.2)) }

        let scroll = UIScrollView()
        scroll.addSubview(content)

        note.textAlignment = .center
        primary.configurationUpdateHandler = { Spring.press($0, $0.isHighlighted) }
        primary.addAction(UIAction { [weak self] _ in self?.tapPrimary() }, for: .primaryActionTriggered)
        let links = UIStackView(arrangedSubviews: [("Terms of Use", Pass.termsURL), ("Privacy Policy", Pass.privacyURL)].map { title, url in
            Self.plainButton(title, Theme.secondary) { UIApplication.shared.open(url) }
        })
        links.spacing = 24
        let linkRow = UIStackView(arrangedSubviews: [links])
        linkRow.axis = .vertical
        linkRow.alignment = .center
        let footer = UIStackView(arrangedSubviews: [note, primary, linkRow])
        footer.axis = .vertical
        footer.spacing = 10
        footer.setCustomSpacing(14, after: note)

        [close, restore, scroll, footer].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            restore.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            restore.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Shelf.margin),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Shelf.margin),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .passChanged, object: nil)
        update()
        loadPosters()
    }

    /// Your own posters when you have enough, otherwise what's popular.
    private func loadPosters() {
        func show(_ titles: [Title]) -> Bool {
            let art = titles.filter { $0.posterPath != nil }.prefix(posters.count)
            guard art.count == posters.count else { return false }
            zip(posters, art).forEach { $0.setImage(TMDB.imageURL($1.posterPath, .poster)) }
            return true
        }
        guard !show(Store.shared.all().map(\.title)) else { return }
        Task {
            if !show((try? await TMDB.shared.titles(Reel.featured)) ?? []) { posterRow.isHidden = true }
        }
    }

    private static func benefit(_ symbol: String, _ title: String, _ detail: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Theme.text
        icon.contentMode = .top
        icon.preferredSymbolConfiguration = .init(font: Theme.text(.title3))
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let name = UILabel.make(Theme.text(.headline, weight: .semibold), Theme.text, lines: 0)
        name.text = title
        let sub = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)
        sub.text = detail
        let text = UIStackView(arrangedSubviews: [name, sub])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.alignment = .top
        row.spacing = 12
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title). \(detail)"
        return row
    }

    private static func plainButton(_ title: String, _ color: UIColor, _ action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = color
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = Theme.text(.subheadline); return a
        }
        return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }

    /// What the button says depends on where you are: new (trial on offer), lapsed, mid-trial, or subscribed.
    @objc private func update() {
        let pass = Pass.shared
        let ends = pass.periodEnds?.formatted(.dateTime.day().month(.wide).year())
        if pass.subscribed {
            if pass.inTrial, let ends {
                note.text = pass.willRenew ? "Your free trial runs until \(ends), then it's \(pass.price) a year. Cancel anytime in Settings." : "Your free trial ends \(ends) and won't renew."
            } else if let ends {
                note.text = pass.willRenew ? "You're in. Renews \(ends) for \(pass.price). Thank you." : "You're in until \(ends). It won't renew."
            } else {
                note.text = "You're in. Thank you."
            }
            primary.configuration?.title = "Done"
        } else if let trial = pass.trialLength {
            note.text = "Free for \(trial), then \(pass.price) a year. Renews automatically; cancel anytime in Settings, at least a day before the trial ends."
            primary.configuration?.title = "Try \(trial) free"
        } else {
            note.text = "\(pass.price) a year. Renews automatically; cancel anytime in Settings."
            primary.configuration?.title = "Subscribe · \(pass.price) a year"
        }
    }

    private func tapPrimary() {
        if Pass.shared.subscribed { dismiss(animated: true); return }
        busy = true
        Task {
            defer { busy = false }
            do {
                switch try await Pass.shared.subscribe() {
                case .unlocked: celebrate()
                case .pending: showMessage("Your purchase is waiting for approval. It'll unlock as soon as it's through.")
                case .cancelled: break
                }
            } catch {
                showMessage(Pass.shared.yearly == nil ? "The store isn't available right now. Try again in a moment." : error.localizedDescription)
            }
        }
    }

    private func restore() {
        busy = true
        Task {
            await Pass.shared.restore()
            busy = false
            if Pass.shared.isUnlocked { celebrate() } else { showMessage("No active pass found for this Apple Account.") }
        }
    }

    private func celebrate() {
        Haptics.success()
        dismiss(animated: true)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
