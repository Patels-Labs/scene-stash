import UIKit

/// System type on true black, as in the TV app. Colour comes from the art.
enum Theme {
    static let bg = UIColor.black
    static let surface = UIColor(white: 0.075, alpha: 1)
    static let surfaceHigh = UIColor(white: 0.13, alpha: 1)
    static let hairline = UIColor(white: 1, alpha: 0.09)
    static let text = UIColor.white
    static let secondary = UIColor(white: 1, alpha: 0.62)
    static let tertiary = UIColor(white: 1, alpha: 0.36)
    /// The amber from the icon. Used sparingly: progress and the selected thing.
    static let accent = UIColor(red: 1.0, green: 0.71, blue: 0.27, alpha: 1)

    static func text(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: text(.largeTitle, weight: .bold), .foregroundColor: text]
        nav.titleTextAttributes = [.font: text(.headline, weight: .semibold), .foregroundColor: text]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}

extension UIFont {
    var monospacedDigits: UIFont {
        let d = fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
        ]]])
        return UIFont(descriptor: d, size: 0)
    }
}

extension UILabel {
    static func make(_ font: UIFont, _ color: UIColor = Theme.text, lines: Int = 1) -> UILabel {
        let l = UILabel()
        l.font = font
        l.textColor = color
        l.numberOfLines = lines
        l.adjustsFontForContentSizeCategory = true
        return l
    }
}
