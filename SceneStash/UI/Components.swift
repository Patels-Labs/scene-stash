import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thunk() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9) }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// The app's one motion curve. Critically damped by default, starts from wherever the view is now, and never
/// blocks touches, so anything can be grabbed or reversed part-way through. Save bounce for something thrown.
enum Spring {
    static func move(response: TimeInterval = 0.4, bounce: CGFloat = 0, delay: TimeInterval = 0, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        let options: UIView.AnimationOptions = [.allowUserInteraction, .beginFromCurrentState]
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, delay: delay, options: options, animations: changes, completion: completion)
        } else {
            UIView.animate(springDuration: response, bounce: bounce, initialSpringVelocity: 0, delay: delay, options: options, animations: changes, completion: completion)
        }
    }

    /// Shows the touch the moment it lands, and lets go a little slower.
    static func press(_ view: UIView, _ down: Bool, scale: CGFloat = 0.97) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        move(response: down ? 0.12 : 0.3) { view.transform = down ? CGAffineTransform(scaleX: scale, y: scale) : .identity }
    }
}

extension UIView {
    func pin(to other: UIView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: other.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -inset),
        ])
    }
}

extension CALayer {
    /// Sizes a layer to its view without the implicit animation a bare layer gets, which otherwise shows
    /// the layer growing out of the corner whenever a cell first lays out.
    func place(_ frame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        CATransaction.commit()
    }
}

extension UIViewController {
    func installBackdrop() {
        view.backgroundColor = Theme.bg
    }

    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't load", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Opens a title's detail with the native zoom transition from `source`.
    func openDetail(_ title: Title, from source: @escaping () -> UIView?) {
        let detail = DetailViewController(title: title)
        detail.preferredTransition = .zoom { _ in source() }
        navigationController?.pushViewController(detail, animated: true)
    }

    /// Long-press menu shared by every poster.
    func titleMenu(_ title: Title) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let current = Store.shared.tracked(title.id, title.mediaType)?.status
            var actions: [UIMenuElement] = (title.unreleased ? [.watchlist] : TrackStatus.allCases).map { status in
                UIAction(title: status.label, image: UIImage(systemName: status.symbol), state: current == status ? .on : .off) { _ in
                    Store.shared.track(title, status: status)
                    Haptics.success()
                }
            }
            if current != nil {
                actions.append(UIAction(title: title.unreleased ? "Remove from Watchlist" : "Remove from Library", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    Store.shared.remove(title)
                })
            }
            return UIMenu(title: title.name, children: actions)
        }
    }
}
