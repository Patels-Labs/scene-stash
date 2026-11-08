import UIKit

/// One family, three widths: SF Pro Compressed for poster-style titles and numerals,
/// SF Pro for reading, SF Pro Expanded for small tracked labels. True black; colour comes from posters.
enum Theme {
    static let bg = UIColor.black
    static let surface = UIColor(white: 0.075, alpha: 1)
    static let surfaceHigh = UIColor(white: 0.13, alpha: 1)
    static let hairline = UIColor(white: 1, alpha: 0.09)
    static let text = UIColor.white
    static let secondary = UIColor(white: 1, alpha: 0.62)
    static let tertiary = UIColor(white: 1, alpha: 0.36)
    /// The ticket amber from the icon. Used sparingly: progress, the stash, the selected thing.
    static let accent = UIColor(red: 1.0, green: 0.71, blue: 0.27, alpha: 1)

    /// Poster-title face. `size` is the default-size point size; it scales with Dynamic Type.
    static func display(_ size: CGFloat, weight: UIFont.Weight = .heavy, relativeTo style: UIFont.TextStyle = .largeTitle) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight, width: .compressed)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font.monospacedDigits)
    }

    static func text(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    /// Small caps-style label. Pair with `UILabel.setCaps` for tracking.
    static func label(_ style: UIFont.TextStyle = .caption2, weight: UIFont.Weight = .semibold) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight, width: .expanded))
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
    /// Uppercased, letter-spaced label text.
    func setCaps(_ string: String?, kern: CGFloat = 1.4) {
        guard let string else { attributedText = nil; return }
        attributedText = NSAttributedString(string: string.uppercased(), attributes: [.kern: kern])
        accessibilityLabel = string
    }

    /// Display text with tight leading, the way poster titles are set.
    func setDisplay(_ string: String?, lineHeight: CGFloat = 0.86) {
        guard let string else { attributedText = nil; return }
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.alignment = textAlignment
        attributedText = NSAttributedString(string: string, attributes: [.paragraphStyle: style])
    }

    static func make(_ font: UIFont, _ color: UIColor = Theme.text, lines: Int = 1) -> UILabel {
        let l = UILabel()
        l.font = font
        l.textColor = color
        l.numberOfLines = lines
        l.adjustsFontForContentSizeCategory = true
        return l
    }
}
