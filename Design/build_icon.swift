// Draws the app icons: a ticket on black, its stub just torn off, with a compressed S.
// The amber one is the app icon; the others are alternate icons that come with the All-Access Pass.
// Run: swift Design/build_icon.swift → writes Design/icon-1024.png, each AppIcon set (opaque, as the App Store
// requires) and a small preview image of each for the in-app picker.
import AppKit

struct Stock { let name: String; let light: CGColor; let base: CGColor; let glow: CGColor; let ink: CGColor }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

let stocks = [
    Stock(name: "AppIcon", light: rgb(1, 0.80, 0.45), base: rgb(1, 0.71, 0.27), glow: rgb(1, 0.6, 0.2, 0.22), ink: rgb(0, 0, 0)),
    Stock(name: "AppIcon-Red", light: rgb(1, 0.45, 0.38), base: rgb(0.86, 0.2, 0.16), glow: rgb(1, 0.25, 0.2, 0.22), ink: rgb(0.12, 0, 0)),
    Stock(name: "AppIcon-Teal", light: rgb(0.62, 0.9, 0.92), base: rgb(0.2, 0.62, 0.68), glow: rgb(0.3, 0.8, 0.85, 0.2), ink: rgb(0, 0.08, 0.1)),
    Stock(name: "AppIcon-Silver", light: rgb(0.97, 0.97, 0.98), base: rgb(0.7, 0.72, 0.76), glow: rgb(0.8, 0.85, 1, 0.16), ink: rgb(0.05, 0.05, 0.08)),
    Stock(name: "AppIcon-Ink", light: rgb(0.2, 0.2, 0.21), base: rgb(0.1, 0.1, 0.11), glow: rgb(1, 0.71, 0.27, 0.16), ink: rgb(1, 0.71, 0.27)),
]

func render(_ stock: Stock, size: Int) -> CGImage {
    let u = CGFloat(size) / 100 // design units: the icon is laid out on a 100×100 grid
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip to top-left origin so the grid reads like the mockup.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // A low light behind the ticket, so it sits in a room rather than on a void.
    let glow = CGGradient(colorsSpace: nil, colors: [stock.glow, stock.glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 50 * u, y: 54 * u), startRadius: 0, endCenter: CGPoint(x: 50 * u, y: 54 * u), endRadius: 52 * u, options: [])

    func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x * u, y: y * u, width: w * u, height: h * u), cornerWidth: r * u, cornerHeight: r * u, transform: nil)
    }
    /// Fills a ticket piece with a soft top-lit stock, minus the notches at the tear line.
    func piece(_ path: CGPath) {
        let notches = CGMutablePath()
        for y: CGFloat in [31, 69] { notches.addEllipse(in: CGRect(x: 59.5 * u, y: (y - 4.5) * u, width: 9 * u, height: 9 * u)) }
        let shape = path.subtracting(notches)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2.5 * u), blur: 6 * u, color: CGColor(gray: 0, alpha: 0.7))
        ctx.setFillColor(stock.base)
        ctx.addPath(shape)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let b = path.boundingBoxOfPath
        let fill = CGGradient(colorsSpace: nil, colors: [stock.light, stock.base] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(fill, start: CGPoint(x: b.midX, y: b.minY), end: CGPoint(x: b.midX, y: b.maxY), options: [])
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.translateBy(x: 50 * u, y: 50 * u)
    ctx.rotate(by: -14 * .pi / 180)
    ctx.translateBy(x: -50 * u, y: -50 * u)

    // The body, with its perforation along the torn edge.
    piece(rr(12, 31, 52, 38, 5))
    ctx.setFillColor(stock.ink.copy(alpha: 0.55)!)
    for i in 0..<6 { ctx.fillEllipse(in: CGRect(x: 62.2 * u, y: (39 + CGFloat(i) * 4.4) * u, width: 1.6 * u, height: 1.6 * u)) }

    // The S, set in the app's display face: SF Pro Compressed Black.
    let font = NSFont.systemFont(ofSize: 46 * u, weight: .black, width: .compressed)
    let s = NSAttributedString(string: "S", attributes: [.font: font, .foregroundColor: NSColor(cgColor: stock.ink)!])
    let line = CTLineCreateWithAttributedString(s)
    let glyph = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.translateBy(x: 38 * u - glyph.midX, y: 50 * u + glyph.midY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // The stub, torn away: dropped and tipped.
    ctx.translateBy(x: 3.5 * u, y: 3.5 * u)
    ctx.translateBy(x: 75 * u, y: 50 * u)
    ctx.rotate(by: 11 * .pi / 180)
    ctx.translateBy(x: -75 * u, y: -50 * u)
    piece(rr(64, 31, 22, 38, 5))
    ctx.restoreGState()
    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("SceneStash/Resources/Assets.xcassets")
let fm = FileManager.default
for stock in stocks {
    let icon = assets.appendingPathComponent("\(stock.name).appiconset")
    try fm.createDirectory(at: icon, withIntermediateDirectories: true)
    try png(render(stock, size: 1024)).write(to: icon.appendingPathComponent("icon.png"))
    try #"{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#
        .write(to: icon.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    // App icons can't be loaded as images at runtime, so the picker gets its own small copy.
    let preview = assets.appendingPathComponent("Preview-\(stock.name).imageset")
    try fm.createDirectory(at: preview, withIntermediateDirectories: true)
    try png(render(stock, size: 240)).write(to: preview.appendingPathComponent("preview.png"))
    try #"{"images":[{"filename":"preview.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
        .write(to: preview.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
try png(render(stocks[0], size: 1024)).write(to: root.appendingPathComponent("Design/icon-1024.png"))
print("wrote \(stocks.count) icons")
