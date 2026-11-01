// Frames raw iPhone screenshots (1320×2868) with a caption for the App Store.
// usage: swift build_screenshots.swift <raw folder> <out folder>
import AppKit

let shots: [(file: String, eyebrow: String, headline: String)] = [
    ("IMG_7615.PNG", "TONIGHT", "YOUR EVENING,\nALREADY PROGRAMMED"),
    ("IMG_7622.PNG", "NOW SHOWING", "IT KEEPS TIME.\nPAUSE FOR ADS."),
    ("IMG_7617.PNG", "STAY SEATED", "KNOW IF THERE'S A\nSCENE AFTER CREDITS"),
    ("IMG_7620.PNG", "PUNCH CARD", "EVERY EPISODE,\nPUNCHED"),
    ("IMG_7623.PNG", "MARATHONS", "PLAN THE WHOLE\nSAGA, BREAKS AND ALL"),
    ("IMG_7618.PNG", "YOUR STASH", "RATE IT ON\nTHE REEL"),
    ("IMG_7627.PNG", "WIDGETS", "TONIGHT ON YOUR\nHOME SCREEN"),
]

let (inDir, outDir) = (CommandLine.arguments[1], CommandLine.arguments[2])
let W = 1320, H = 2868
let amber = CGColor(red: 0.96, green: 0.71, blue: 0.27, alpha: 1)
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func text(_ s: String, font: NSFont, color: CGColor, kern: CGFloat, lineHeight: CGFloat) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.minimumLineHeight = lineHeight
    p.maximumLineHeight = lineHeight
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: kern, .paragraphStyle: p])
}

for (i, shot) in shots.enumerated() {
    guard let raw = NSImage(contentsOfFile: "\(inDir)/\(shot.file)")?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("missing \(shot.file)"); continue
    }
    // Opaque RGB: App Store Connect rejects screenshots with an alpha channel.
    let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.setFillColor(CGColor(gray: 0.03, alpha: 1))
    c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // A warm projector glow behind the caption.
    let glow = CGGradient(colorsSpace: nil, colors: [amber.copy(alpha: 0.28)!, amber.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: H - 300), startRadius: 0,
                         endCenter: CGPoint(x: W / 2, y: H - 300), endRadius: 1100, options: [])

    // Caption (AppKit draws top-down in a flipped graphics context).
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    let eyebrow = text(shot.eyebrow, font: .systemFont(ofSize: 44, weight: .semibold, width: .expanded), color: amber, kern: 9, lineHeight: 52)
    let headline = text(shot.headline, font: .systemFont(ofSize: 132, weight: .black, width: .compressed), color: .white, kern: 0, lineHeight: 132)
    eyebrow.draw(in: CGRect(x: 60, y: H - 200, width: W - 120, height: 60))
    headline.draw(in: CGRect(x: 60, y: H - 520, width: W - 120, height: 290))
    NSGraphicsContext.current = nil

    // The screenshot, scaled down with rounded corners and a hairline edge.
    let scale = 0.78, w = Double(W) * scale, h = Double(H) * scale
    let frame = CGRect(x: (Double(W) - w) / 2, y: 70, width: w, height: h)
    let path = CGPath(roundedRect: frame, cornerWidth: 120, cornerHeight: 120, transform: nil)
    c.saveGState()
    c.setShadow(offset: .zero, blur: 80, color: CGColor(gray: 0, alpha: 0.9))
    c.addPath(path); c.setFillColor(.black); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(path); c.clip()
    c.draw(raw, in: frame)
    c.restoreGState()
    c.addPath(path); c.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); c.setLineWidth(3); c.strokePath()

    let name = String(format: "%02d-%@.png", i + 1, shot.eyebrow.lowercased().replacingOccurrences(of: " ", with: "-"))
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print(name)
}
