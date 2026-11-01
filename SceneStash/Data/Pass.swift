import StoreKit
import UIKit

extension Notification.Name {
    static let passChanged = Notification.Name("passChanged")
}

/// The All-Access Pass: a one-off $1.99 unlock, with a free seven-day trial before it.
/// Apple only offers trials on subscriptions, so the trial is its own free, non-consumable product
/// that unlocks the extras for seven days from when it was claimed.
final class Pass {
    static let shared = Pass()
    static let lifetimeID = "com.heetpatel.scenestash.pass"
    static let trialID = "com.heetpatel.scenestash.trial"
    static let trialLength: TimeInterval = 7 * 24 * 3600

    private(set) var lifetime: Product?
    private(set) var trial: Product?
    private(set) var owned = false
    /// When the trial was claimed, if it ever was. Claiming it twice isn't possible: it's a non-consumable.
    private(set) var trialStarted: Date?
    private var updates: Task<Void, Never>?

    var trialEnds: Date? { trialStarted?.addingTimeInterval(Self.trialLength) }
    var trialActive: Bool { trialEnds.map { $0 > .now } ?? false }
    var isUnlocked: Bool { owned || trialActive }

    private init() {}

    /// Call once at launch: loads products, reads what's owned, and listens for purchases made elsewhere.
    func start() {
        updates = Task {
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await refresh()
            }
        }
        Task {
            let products = (try? await Product.products(for: [Self.lifetimeID, Self.trialID])) ?? []
            lifetime = products.first { $0.id == Self.lifetimeID }
            trial = products.first { $0.id == Self.trialID }
            await refresh()
        }
    }

    func refresh() async {
        var owned = false, trialStarted: Date?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let t) = entitlement, t.revocationDate == nil else { continue }
            if t.productID == Self.lifetimeID { owned = true }
            if t.productID == Self.trialID { trialStarted = t.purchaseDate }
        }
        self.owned = owned
        self.trialStarted = trialStarted
        NotificationCenter.default.post(name: .passChanged, object: nil)
    }

    enum Outcome { case unlocked, cancelled, pending }

    func buy(_ product: Product) async throws -> Outcome {
        switch try await product.purchase() {
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
    /// Runs `action` if the pass is unlocked; otherwise shows the paywall.
    func withPass(_ action: () -> Void) {
        if Pass.shared.isUnlocked { action() } else { present(PaywallViewController(), animated: true) }
    }
}
