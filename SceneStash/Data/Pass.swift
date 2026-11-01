import StoreKit
import UIKit

extension Notification.Name {
    static let passChanged = Notification.Name("passChanged")
}

/// The All-Access Pass: a yearly auto-renewing subscription. New subscribers get a free trial, set up in
/// App Store Connect as the subscription's introductory offer, so Apple handles eligibility and the switch to paid.
final class Pass {
    static let shared = Pass()
    static let yearlyID = "com.heetpatel.scenestash.yearly"
    static let privacyURL = URL(string: "https://github.com/patelheet30/scene-stash/blob/main/docs/privacy.md")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private(set) var yearly: Product?
    /// The current period: whether it's the free trial, when it ends, and whether it will renew.
    private(set) var subscribed = false
    private(set) var inTrial = false
    private(set) var periodEnds: Date?
    private(set) var willRenew = true
    /// New subscribers only; Apple remembers who's had the trial.
    private(set) var trialEligible = true
    private var updates: Task<Void, Never>?

    var isUnlocked: Bool {
        #if DEBUG
        // Local previews only: launch with `-PreviewUnlocked YES`. Not compiled into release builds.
        if UserDefaults.standard.bool(forKey: "PreviewUnlocked") { return true }
        #endif
        return subscribed
    }

    /// "2 weeks", from the introductory offer as configured in App Store Connect.
    var trialLength: String? {
        #if DEBUG
        // Local previews only: `-PreviewTrial "2 weeks"` shows the trial wording without a store connection.
        if let preview = UserDefaults.standard.string(forKey: "PreviewTrial") { return preview }
        #endif
        guard trialEligible, let offer = yearly?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let unit = switch p.unit { case .day: "day"; case .week: "week"; case .month: "month"; case .year: "year"; @unknown default: "day" }
        return p.value == 1 ? "1 \(unit)" : "\(p.value) \(unit)s"
    }

    var price: String { yearly?.displayPrice ?? "$2.99" }

    private init() {}

    /// Call once at launch: loads the product, reads the subscription, and listens for changes made elsewhere.
    func start() {
        updates = Task {
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await refresh()
            }
        }
        Task {
            yearly = (try? await Product.products(for: [Self.yearlyID]))?.first
            await refresh()
        }
    }

    func refresh() async {
        var active: Transaction?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Self.yearlyID, t.revocationDate == nil { active = t }
        }
        subscribed = active != nil
        inTrial = active?.offer?.paymentMode == .freeTrial
        periodEnds = active?.expirationDate
        if let status = try? await yearly?.subscription?.status.first, case .verified(let renewal) = status.renewalInfo {
            willRenew = renewal.willAutoRenew
        }
        trialEligible = await yearly?.subscription?.isEligibleForIntroOffer ?? true
        NotificationCenter.default.post(name: .passChanged, object: nil)
    }

    enum Outcome { case unlocked, cancelled, pending }

    func subscribe() async throws -> Outcome {
        // The launch fetch can fail (offline, or the product wasn't live yet), so try again before giving up.
        if yearly == nil { yearly = try? await Product.products(for: [Self.yearlyID]).first }
        guard let yearly else { throw StoreKitError.notAvailableInStorefront }
        switch try await yearly.purchase() {
        case .success(let result):
            guard case .verified(let t) = result else { throw StoreKitError.notEntitled }
            await t.finish()
            await refresh()
            return .unlocked
        case .pending: return .pending
        default: return .cancelled
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}

extension UIViewController {
    /// Runs `action` if the pass is active; otherwise shows the paywall.
    func withPass(_ action: () -> Void) {
        if Pass.shared.isUnlocked { action() } else { present(PaywallViewController(), animated: true) }
    }
}
