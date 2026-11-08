import CloudKit
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Theme.accent
        window.overrideUserInterfaceStyle = .dark
        let tabs = UITabBarController(tabs: [
            UITab(title: "Tonight", image: UIImage(systemName: "popcorn"), identifier: "tonight") { _ in Self.nav(TonightViewController()) },
            UITab(title: "Library", image: UIImage(systemName: "rectangle.stack"), identifier: "stash") { _ in Self.nav(StashViewController()) },
            UITab(title: "Nights", image: UIImage(systemName: "person.2"), identifier: "nights") { _ in Self.nav(NightsViewController()) },
            UISearchTab { _ in Self.nav(DiscoverViewController()) },
        ])
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        Task { await Store.shared.backfillRuntimes() }
        self.window = window
        Task { await Store.shared.loadIdentity() }
        if let metadata = connectionOptions.cloudKitShareMetadata { Store.shared.accept(metadata) }
        if !Prefs.onboarded {
            // Next runloop, once the tab controller is in the window hierarchy.
            DispatchQueue.main.async { tabs.present(OnboardingViewController(), animated: false) }
        }
    }

    /// Tapping a friend's movie-night link opens the app here.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Store.shared.accept(metadata)
    }

    // Keep the film's saved place current with any Start now session.
    func sceneWillResignActive(_ scene: UIScene) { WatchSession.shared.savePosition() }
    func sceneDidBecomeActive(_ scene: UIScene) {
        WatchSession.shared.savePosition()
        Store.shared.updateFromNights()
    }

    private static func nav(_ root: UIViewController) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}
