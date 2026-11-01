import StoreKit
import UIKit

/// The All-Access Pass, sold as a foil ticket: tilt it, read the bill, buy it once.
final class PaywallViewController: UIViewController {
    private let ticket = TiltCardView()
    private let note = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
    private let primary = PillButton("Start free trial")
    private let secondary = PillButton("Buy now", inverted: true)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var busy = false { didSet { [primary, secondary].forEach { $0.isEnabled = !busy }; busy ? spinner.startAnimating() : spinner.stopAnimating() } }

    private static let bill: [(String, String)] = [
        ("Your year, on film", "A year-end reel of everything you watched, ready to share."),
        ("Now showing", "A Live Activity with time left and when it ends, plus Tonight on your Home Screen."),
        ("Marathons", "Plan a whole franchise or season across nights, with breaks."),
        ("The stub book", "Every film you finish becomes a dated ticket stub, with your rating and a note."),
        ("Premiere alerts & icons", "A nudge the night a new episode lands, and a box of alternate ticket icons."),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [Theme.accent.withAlphaComponent(0.4).cgColor, Theme.accent.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(x: -120, y: -40, width: 640, height: 560)
        view.layer.addSublayer(glow)

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = .init(top: 64, leading: 20, bottom: 260, trailing: 20)

        ticket.imageView.image = Self.ticketImage(price: "$1.99")
        ticket.cornerRadius = 16
        ticket.maxAngle = 0.2
        ticket.foil = true
        ticket.isAccessibilityElement = true
        ticket.accessibilityLabel = "All-Access Pass. Admit one, valid forever."
        let ticketRow = UIStackView(arrangedSubviews: [ticket])
        ticketRow.axis = .vertical
        ticketRow.alignment = .center
        ticket.heightAnchor.constraint(equalTo: ticket.widthAnchor, multiplier: 176 / 330.0).isActive = true
        ticket.transform = CGAffineTransform(rotationAngle: -0.07)

        let headline = UILabel.make(Theme.display(62, weight: .black), Theme.text, lines: 0)
        let text = NSMutableAttributedString(string: "ONE TICKET.\n", attributes: [.foregroundColor: Theme.text])
        text.append(NSAttributedString(string: "EVERY SHOW, FOREVER.", attributes: [.foregroundColor: Theme.tertiary]))
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 0.86
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        headline.attributedText = text
        headline.accessibilityTraits = .header
        let body = UILabel.make(Theme.text(.subheadline), Theme.secondary, lines: 0)
        body.text = "Tracking stays free. The pass adds the extras, for one small price, once."
        let caption = UILabel.make(Theme.label(.caption2, weight: .bold), Theme.accent)
        caption.setCaps("On the bill")

        [ticketRow, headline, body, caption].forEach(content.addArrangedSubview)
        ticket.widthAnchor.constraint(equalTo: content.layoutMarginsGuide.widthAnchor, constant: -10).isActive = true
        content.setCustomSpacing(40, after: ticketRow)
        content.setCustomSpacing(30, after: body)
        content.setCustomSpacing(2, after: caption)
        for (i, item) in Self.bill.enumerated() { content.addArrangedSubview(Self.line(i + 1, item.0, item.1, last: i == Self.bill.count - 1)) }

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

        buildFooter()
        buildTopBar()
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .passChanged, object: nil)
        update()
    }

    private static func line(_ n: Int, _ title: String, _ detail: String, last: Bool) -> UIView {
        let number = UILabel.make(Theme.display(30, weight: .black), Theme.tertiary)
        number.text = String(format: "%02d", n)
        number.widthAnchor.constraint(equalToConstant: 38).isActive = true
        let name = UILabel.make(Theme.display(26, weight: .black), Theme.text, lines: 0)
        name.text = title.uppercased()
        let sub = UILabel.make(Theme.text(.footnote), Theme.secondary, lines: 0)
        sub.text = detail
        let text = UIStackView(arrangedSubviews: [name, sub])
        text.axis = .vertical
        text.spacing = 4
        let row = UIStackView(arrangedSubviews: [number, text])
        row.alignment = .top
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 14, leading: 0, bottom: 14, trailing: 0)
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title). \(detail)"
        if !last {
            let rule = UIView()
            rule.backgroundColor = Theme.hairline
            row.addSubview(rule)
            rule.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rule.leadingAnchor.constraint(equalTo: row.leadingAnchor), rule.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                rule.bottomAnchor.constraint(equalTo: row.bottomAnchor), rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            ])
        }
        return row
    }

    private func buildTopBar() {
        let close = UIButton(configuration: .glass())
        close.configuration?.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        let restore = UIButton(type: .system)
        restore.setTitle("RESTORE", for: .normal)
        restore.titleLabel?.font = Theme.label(.caption2, weight: .bold)
        restore.tintColor = Theme.secondary
        restore.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)
        [close, restore].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            restore.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            restore.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
    }

    private func buildFooter() {
        let fade = CAGradientLayer()
        fade.colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        fade.locations = [0, 0.2, 1]
        let footer = CardView()
        footer.layer.addSublayer(fade)
        footer.onLayout = { fade.frame = $0 }
        note.textAlignment = .center
        primary.addAction(UIAction { [weak self] _ in self?.tapPrimary() }, for: .primaryActionTriggered)
        secondary.addAction(UIAction { [weak self] _ in self?.buy(Pass.shared.lifetime) }, for: .primaryActionTriggered)
        let terms = UIButton(type: .system)
        terms.setTitle("TERMS OF USE", for: .normal)
        terms.titleLabel?.font = Theme.label(.caption2, weight: .bold)
        terms.tintColor = Theme.tertiary
        terms.addAction(UIAction { _ in
            UIApplication.shared.open(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [note, primary, secondary, terms])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(14, after: note)
        footer.addSubview(stack)
        footer.addSubview(spinner)
        view.addSubview(footer)
        [footer, stack, spinner].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            spinner.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -4),
        ])
    }

    /// What the buttons say depends on where you are: never tried, mid-trial, trial over, or owned.
    @objc private func update() {
        let pass = Pass.shared
        let price = pass.lifetime?.displayPrice ?? "$1.99"
        ticket.imageView.image = Self.ticketImage(price: price)
        primary.isHidden = false
        secondary.isHidden = false
        if pass.owned {
            note.text = "You're in. Every extra, for good. Thank you."
            primary.configuration?.title = "Done"
            secondary.isHidden = true
        } else if pass.trialActive, let ends = pass.trialEnds {
            note.text = "Your trial runs until \(ends.formatted(.dateTime.weekday(.wide).day().month())). Keep everything for \(price), once."
            primary.configuration?.title = "Keep it · \(price)"
            secondary.isHidden = true
        } else if pass.trialStarted != nil || (pass.trial == nil && pass.lifetime != nil) {
            note.text = "\(price) once. No subscription."
            primary.configuration?.title = "Buy now · \(price)"
            secondary.isHidden = true
        } else {
            note.text = "Free for 7 days, then \(price) once. No subscription."
            primary.configuration?.title = "Start free trial"
            secondary.configuration?.title = "Buy now · \(price)"
        }
    }

    private func tapPrimary() {
        let pass = Pass.shared
        if pass.owned { dismiss(animated: true); return }
        let canTrial = pass.trialStarted == nil && pass.trial != nil
        buy(canTrial ? pass.trial : pass.lifetime)
    }

    private func buy(_ product: Product?) {
        guard let product else {
            showMessage("The store isn't available right now. Try again in a moment.")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                switch try await Pass.shared.buy(product) {
                case .unlocked: celebrate()
                case .pending: showMessage("Your purchase is waiting for approval. It'll unlock as soon as it's through.")
                case .cancelled: break
                }
            } catch {
                showMessage(error.localizedDescription)
            }
        }
    }

    private func restore() {
        busy = true
        Task {
            await Pass.shared.restore()
            busy = false
            if Pass.shared.isUnlocked { celebrate() } else { showMessage("No pass found for this Apple Account.") }
        }
    }

    /// The ticket flashes its foil and the screen closes.
    private func celebrate() {
        Haptics.success()
        ticket.revealFoil()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.dismiss(animated: true) }
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// The pass itself, printed: amber stock, "All-Access" in the display face, a perforated $1.99 stub.
    static func ticketImage(price: String) -> UIImage {
        let size = CGSize(width: 660, height: 352)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let stubX: CGFloat = 492
            let colors = [UIColor(red: 1, green: 0.82, blue: 0.48, alpha: 1), Theme.accent, UIColor(red: 0.89, green: 0.6, blue: 0.17, alpha: 1)].map(\.cgColor)
            let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 0.5, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor(white: 0, alpha: 0.45).setFill()
            for y in stride(from: CGFloat(18), to: size.height - 10, by: 18) {
                UIBezierPath(ovalIn: CGRect(x: stubX - 3, y: y, width: 6, height: 6)).fill()
            }
            func draw(_ text: String, _ font: UIFont, at point: CGPoint, kern: CGFloat = 0, alpha: CGFloat = 1, centeredIn width: CGFloat? = nil) {
                let s = NSAttributedString(string: text, attributes: [.font: font, .kern: kern, .foregroundColor: UIColor(white: 0, alpha: alpha)])
                let x = width.map { point.x + ($0 - s.size().width) / 2 } ?? point.x
                s.draw(at: CGPoint(x: x, y: point.y))
            }
            let small = UIFont.systemFont(ofSize: 17, weight: .bold, width: .expanded)
            draw("SCENE STASH", small, at: CGPoint(x: 36, y: 32), kern: 3)
            draw("NO. 000417", small, at: CGPoint(x: 330, y: 32), kern: 3)
            draw("ADMIT ONE", small, at: CGPoint(x: 36, y: 168), kern: 3, alpha: 0.65)
            draw("ALL-ACCESS", .systemFont(ofSize: 104, weight: .black, width: .compressed), at: CGPoint(x: 32, y: 182))
            draw("VALID FOREVER · EVERY SCREEN", small, at: CGPoint(x: 36, y: 300), kern: 3)
            let stubW = size.width - stubX
            draw("ONCE", small, at: CGPoint(x: stubX, y: 110), kern: 3, centeredIn: stubW)
            draw(price, .systemFont(ofSize: 72, weight: .black, width: .compressed), at: CGPoint(x: stubX, y: 136), centeredIn: stubW)
            draw("LIFETIME", small, at: CGPoint(x: stubX, y: 226), kern: 3, centeredIn: stubW)
        }
    }
}
