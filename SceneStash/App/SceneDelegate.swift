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
            UITab(title: "Library", image: UIImage(systemName: "rectangle.stack"), identifier: "stash") { _ in Self.nav(LibraryViewController()) },
            UITab(title: "Nights", image: UIImage(systemName: "person.2"), identifier: "nights") { _ in Self.nav(NightsViewController()) },
            UISearchTab { _ in Self.nav(SearchViewController()) },
        ])
        window.rootViewController = tabs
        #if DEBUG
        // Local previews: `-StartTab nights` opens on that tab, so each screen can be checked without clicking.
        if let start = UserDefaults.standard.string(forKey: "StartTab") { tabs.selectedTab = tabs.tabs.first { $0.identifier == start } }
        #endif
        window.makeKeyAndVisible()
        Task { await Store.shared.backfillRuntimes() }
        self.window = window
        Task { await Store.shared.loadIdentity() }
        if let metadata = connectionOptions.cloudKitShareMetadata { Store.shared.accept(metadata) }
        if let url = connectionOptions.urlContexts.first?.url, Prefs.onboarded { DispatchQueue.main.async { self.open(url) } }
        if !Prefs.onboarded {
            // Next runloop, once the tab controller is in the window hierarchy.
            DispatchQueue.main.async { tabs.present(OnboardingViewController(), animated: false) }
        }
    }

    /// Tapping a friend's movie-night link opens the app here.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Store.shared.accept(metadata)
    }

    /// A tapped widget: scenestash://title/<movie|tv>/<id>?name=…
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.first.map { open($0.url) }
    }

    private func open(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.host == "title", parts.count == 2, let type = MediaType(rawValue: parts[0]), let id = Int(parts[1]),
              let tabs = window?.rootViewController as? UITabBarController, tabs.presentedViewController == nil || Prefs.onboarded else { return }
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value ?? ""
        tabs.dismiss(animated: false)
        tabs.selectedTab = tabs.tabs.first
        guard let nav = tabs.selectedViewController as? UINavigationController else { return }
        nav.popToRootViewController(animated: false)
        nav.pushViewController(DetailViewController(title: Title(id: id, mediaType: type, name: name, posterPath: nil)), animated: false)
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
