import UIKit

/// Every cold launch: the icon's ticket tears on black, then a ticket-shaped hole opens in the black and the app
/// rushes through it. Only the curtain is masked, never the app's own views, so its glass bars render untouched.
final class LaunchCurtain: UIView {
    private let backing = UIView()
    private let ticket = Ticket()
    private let tilt = CGAffineTransform(rotationAngle: -14 * .pi / 180)

    /// Covers the window from the first frame; `play()` runs it once the scene is actually on screen.
    /// Nil with Reduce Motion.
    static func install(in window: UIWindow) -> LaunchCurtain? {
        guard !UIAccessibility.isReduceMotionEnabled else { return nil }
        let curtain = LaunchCurtain()
        window.addSubview(curtain)
        curtain.pin(to: window)
        return curtain
    }

    private init() {
        super.init(frame: .zero)
        accessibilityElementsHidden = true
        backing.backgroundColor = Theme.bg // the launch screen's black, so the cut from it is invisible
        addSubview(backing)
        backing.pin(to: self)
        addSubview(ticket)
        ticket.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ticket.centerXAnchor.constraint(equalTo: centerXAnchor),
            ticket.centerYAnchor.constraint(equalTo: centerYAnchor),
            ticket.widthAnchor.constraint(equalToConstant: 220),
            ticket.heightAnchor.constraint(equalTo: ticket.widthAnchor),
        ])
        ticket.alpha = 0
        ticket.transform = tilt.scaledBy(x: 0.8, y: 0.8)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// About 1.6s, then the curtain removes itself.
    func play() {
        Task {
            Spring.move(response: 0.5, bounce: 0.15) {
                self.ticket.alpha = 1
                self.ticket.transform = self.tilt
            }
            try? await Task.sleep(for: .seconds(0.5))
            Haptics.thunk()
            ticket.tear()
            try? await Task.sleep(for: .seconds(0.4))
            let reveal = open()
            try? await Task.sleep(for: .seconds(reveal))
            removeFromSuperview()
        }
    }

    /// Cuts the whole ticket's outline out of the black, laid over the drawn ticket, and grows it past the corners.
    private func open() -> TimeInterval {
        layoutIfNeeded()
        let u = ticket.bounds.width / 100
        let hole = CAShapeLayer()
        hole.bounds = ticket.bounds
        hole.position = ticket.center
        let path = CGMutablePath()
        path.addRect(ticket.bounds.insetBy(dx: -4000, dy: -4000)) // stays black everywhere but the hole
        path.addPath(Ticket.shape(CGRect(x: 12, y: 31, width: 74, height: 38), unit: u))
        hole.path = path
        hole.fillRule = .evenOdd
        // Big enough that the ticket's short side, and its notches, clear the window's corners.
        let scale = 1.3 * hypot(bounds.width, bounds.height) / (38 * u)
        let start = CATransform3DMakeAffineTransform(tilt)
        let end = CATransform3DScale(start, scale, scale, 1)
        hole.transform = end
        backing.layer.mask = hole
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = start
        grow.toValue = end
        grow.duration = 0.7
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.9, 0.35) // eases out of the ticket, then rushes
        hole.add(grow, forKey: "grow")
        isUserInteractionEnabled = false
        Spring.move(response: 0.25) { self.ticket.alpha = 0 }
        return grow.duration
    }
}
