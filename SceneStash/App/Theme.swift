import UIKit

enum Theme {
    static let ink = UIColor(red: 0.047, green: 0.043, blue: 0.051, alpha: 1)
    static let inkRaised = UIColor(red: 0.09, green: 0.08, blue: 0.085, alpha: 1)
    static let amber = UIColor(red: 1.0, green: 0.69, blue: 0.235, alpha: 1)
    static let amberDeep = UIColor(red: 0.79, green: 0.46, blue: 0.12, alpha: 1)
    static let paper = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1)
    static let muted = UIColor(white: 1, alpha: 0.55)

    /// New York serif, scaled for Dynamic Type.
    static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let desc = base.fontDescriptor.withDesign(.serif)?
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]) ?? base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: desc, size: base.pointSize))
    }

    static func sans(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: base.pointSize, weight: weight))
    }

    /// Monospaced "ticket print" text.
    static func mono(_ style: UIFont.TextStyle, weight: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .monospacedSystemFont(ofSize: base.pointSize, weight: weight))
    }

    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: serif(.largeTitle), .foregroundColor: paper]
        nav.titleTextAttributes = [.font: serif(.headline), .foregroundColor: paper]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
