// Draws the app icon: an amber ticket on black, its stub just torn off, with a compressed S.
// Run: swift Design/build_icon.swift  → writes Design/icon-1024.png and the AppIcon asset (opaque, as the App Store requires).
import AppKit

let size = 1024
let u = CGFloat(size) / 100 // design units: the icon is laid out on a 100×100 grid
let amber = CGColor(red: 1.0, green: 0.71, blue: 0.27, alpha: 1)
let amberLight = CGColor(red: 1.0, green: 0.80, blue: 0.45, alpha: 1)

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip to top-left origin so the grid reads like the mockup.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
// A low warm light behind the ticket, so it sits in a room rather than on a void.
let glow = CGGradient(colorsSpace: nil, colors: [CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.22), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 50 * u, y: 54 * u), startRadius: 0, endCenter: CGPoint(x: 50 * u, y: 54 * u), endRadius: 52 * u, options: [])

func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x * u, y: y * u, width: w * u, height: h * u), cornerWidth: r * u, cornerHeight: r * u, transform: nil)
}

/// Fills a ticket piece with a soft top-lit amber, minus the notches at the tear line.
func piece(_ path: CGPath, notchX: CGFloat, top: CGFloat, bottom: CGFloat) {
    let notches = CGMutablePath()
    for y in [top, bottom] { notches.addEllipse(in: CGRect(x: (notchX - 4.5) * u, y: (y - 4.5) * u, width: 9 * u, height: 9 * u)) }
    let shape = path.subtracting(notches)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 2.5 * u), blur: 6 * u, color: CGColor(gray: 0, alpha: 0.7))
    ctx.setFillColor(amber)
    ctx.addPath(shape)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bounds = path.boundingBoxOfPath
    let fill = CGGradient(colorsSpace: nil, colors: [amberLight, amber] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fill, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
    ctx.restoreGState()
}

ctx.saveGState()
ctx.translateBy(x: 50 * u, y: 50 * u)
ctx.rotate(by: -14 * .pi / 180)
ctx.translateBy(x: -50 * u, y: -50 * u)

// The body.
piece(rr(12, 31, 52, 38, 5), notchX: 64, top: 31, bottom: 69)
// Perforation along the torn edge.
ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
for i in 0..<6 { ctx.fillEllipse(in: CGRect(x: 62.2 * u, y: (39 + CGFloat(i) * 4.4) * u, width: 1.6 * u, height: 1.6 * u)) }

// The S, set in the app's display face: SF Pro Compressed Black.
let font = NSFont.systemFont(ofSize: 46 * u, weight: .black, width: .compressed)
let s = NSAttributedString(string: "S", attributes: [.font: font, .foregroundColor: NSColor.black])
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
piece(rr(64, 31, 22, 38, 5), notchX: 64, top: 31, bottom: 69)
ctx.restoreGState()

let image = ctx.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
try png.write(to: root.appendingPathComponent("Design/icon-1024.png"))
try png.write(to: root.appendingPathComponent("SceneStash/Resources/Assets.xcassets/AppIcon.appiconset/icon.png"))
print("wrote icon")
