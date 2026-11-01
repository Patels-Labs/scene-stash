import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Theme.amber
        window.overrideUserInterfaceStyle = .dark
        let tabs = UITabBarController(tabs: [
            UITab(title: "Tonight", image: UIImage(systemName: "popcorn"), identifier: "tonight") { _ in Self.nav(TonightViewController()) },
            UITab(title: "Stash", image: UIImage(systemName: "ticket"), identifier: "stash") { _ in Self.nav(StashViewController()) },
            UISearchTab { _ in Self.nav(DiscoverViewController()) },
        ])
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        if !Prefs.onboarded {
            // Next runloop, once the tab controller is in the window hierarchy.
            DispatchQueue.main.async { tabs.present(OnboardingViewController(), animated: false) }
        }
    }

    private static func nav(_ root: UIViewController) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}
