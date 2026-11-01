// Draws the app icons: a ticket on black, its stub just torn off, with a compressed S.
// The amber one is the app icon; the others are alternate icons that come with the All-Access Pass.
// Run: swift Design/build_icon.swift → writes Design/icon-1024.png, each AppIcon set (opaque, as the App Store
// requires) and a small preview image of each for the in-app picker.
import AppKit

/// `back` draws behind the ticket and `front` over it, both on the 100-unit grid (`u` points per unit).
struct Stock {
    let name: String; let light: CGColor; let base: CGColor; let glow: CGColor; let ink: CGColor
    var back: ((CGContext, CGFloat) -> Void)? = nil
    var front: ((CGContext, CGFloat) -> Void)? = nil
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

let stocks = [
    Stock(name: "AppIcon", light: rgb(1, 0.80, 0.45), base: rgb(1, 0.71, 0.27), glow: rgb(1, 0.6, 0.2, 0.22), ink: rgb(0, 0, 0)),
    Stock(name: "AppIcon-Red", light: rgb(1, 0.45, 0.38), base: rgb(0.86, 0.2, 0.16), glow: rgb(1, 0.25, 0.2, 0.22), ink: rgb(0.12, 0, 0)),
    Stock(name: "AppIcon-Teal", light: rgb(0.62, 0.9, 0.92), base: rgb(0.2, 0.62, 0.68), glow: rgb(0.3, 0.8, 0.85, 0.2), ink: rgb(0, 0.08, 0.1)),
    Stock(name: "AppIcon-Silver", light: rgb(0.97, 0.97, 0.98), base: rgb(0.7, 0.72, 0.76), glow: rgb(0.8, 0.85, 1, 0.16), ink: rgb(0.05, 0.05, 0.08)),
    Stock(name: "AppIcon-Ink", light: rgb(0.2, 0.2, 0.21), base: rgb(0.1, 0.1, 0.11), glow: rgb(1, 0.71, 0.27, 0.16), ink: rgb(1, 0.71, 0.27)),
]

// MARK: Holiday stock: only offered in the app from two weeks before each holiday to a week after.

/// Deterministic scatter so the icons render the same every time.
struct Scatter {
    var seed: UInt64
    mutating func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
}

func dots(_ c: CGContext, _ u: CGFloat, seed: UInt64, count: Int, colors: [CGColor], size: ClosedRange<CGFloat>, glow: Bool = false) {
    var r = Scatter(seed: seed)
    for i in 0..<count {
        let x = r.next() * 100, y = r.next() * 100, d = size.lowerBound + r.next() * (size.upperBound - size.lowerBound)
        let color = colors[i % colors.count]
        c.saveGState()
        if glow { c.setShadow(offset: .zero, blur: d * 2 * u, color: color) }
        c.setFillColor(color)
        c.fillEllipse(in: CGRect(x: (x - d / 2) * u, y: (y - d / 2) * u, width: d * u, height: d * u))
        c.restoreGState()
    }
}

func star(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor) {
    let p = CGMutablePath()
    for i in 0..<10 {
        let a = CGFloat(i) * .pi / 5 - .pi / 2, rad = (i % 2 == 0 ? r : r * 0.45) * u
        let pt = CGPoint(x: x * u + cos(a) * rad, y: y * u + sin(a) * rad)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    c.setFillColor(color); c.addPath(p); c.fillPath()
}

func burst(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor) {
    c.setStrokeColor(color); c.setLineWidth(1.3 * u); c.setLineCap(.round)
    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6
        c.move(to: CGPoint(x: (x + cos(a) * r * 0.35) * u, y: (y + sin(a) * r * 0.35) * u))
        c.addLine(to: CGPoint(x: (x + cos(a) * r) * u, y: (y + sin(a) * r) * u))
    }
    c.strokePath()
    c.setFillColor(color)
    c.fillEllipse(in: CGRect(x: (x - 1.2) * u, y: (y - 1.2) * u, width: 2.4 * u, height: 2.4 * u))
}

let gold = rgb(1, 0.82, 0.42), cream = rgb(1, 0.96, 0.86)

/// A soft round glow: colour at the centre fading to nothing. Overlapping a few makes powder or haze.
func soft(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor) {
    let g = CGGradient(colorsSpace: nil, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: x * u, y: y * u), startRadius: 0, endCenter: CGPoint(x: x * u, y: y * u), endRadius: r * u, options: [])
}

/// A peony firework: rays of sparks that grow brighter toward their tips, a hot core, a few falling embers.
func firework(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, colors: [CGColor], rays: Int = 18, seed: UInt64) {
    var rnd = Scatter(seed: seed)
    soft(c, u, x: x, y: y, r: r * 0.9, color: colors[0].copy(alpha: 0.18)!)
    for i in 0..<rays {
        let a = CGFloat(i) / CGFloat(rays) * 2 * .pi + rnd.next() * 0.15
        let len = r * (0.78 + rnd.next() * 0.22)
        let color = colors[i % colors.count]
        for k in 1...9 {
            let t = CGFloat(k) / 9
            let d = 0.25 + 0.75 * t * t
            c.saveGState()
            if k == 9 { c.setShadow(offset: .zero, blur: 2.5 * u, color: color) }
            c.setFillColor(color.copy(alpha: 0.2 + 0.8 * t)!)
            let px = x + cos(a) * len * t, py = y + sin(a) * len * t + t * t * r * 0.08 // a little droop
            c.fillEllipse(in: CGRect(x: (px - d / 2) * u, y: (py - d / 2) * u, width: d * u, height: d * u))
            c.restoreGState()
        }
    }
    soft(c, u, x: x, y: y, r: r * 0.22, color: rgb(1, 1, 1, 0.9))
    for _ in 0..<6 {
        let px = x + (rnd.next() - 0.5) * r * 1.4, py = y + r * (0.6 + rnd.next() * 0.6)
        c.setFillColor(colors[0].copy(alpha: 0.6)!)
        c.fillEllipse(in: CGRect(x: px * u, y: py * u, width: 0.6 * u, height: 0.6 * u))
    }
}

/// A clay diya with a patterned rim and a living flame.
func diya(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, s: CGFloat) {
    soft(c, u, x: x, y: y - 4 * s, r: 9 * s, color: rgb(1, 0.6, 0.15, 0.55))
    let bowl = CGMutablePath()
    bowl.move(to: CGPoint(x: (x - 6 * s) * u, y: y * u))
    bowl.addQuadCurve(to: CGPoint(x: (x + 7.5 * s) * u, y: (y - 1.2 * s) * u), control: CGPoint(x: x * u, y: (y + 7 * s) * u))
    bowl.addQuadCurve(to: CGPoint(x: (x - 6 * s) * u, y: y * u), control: CGPoint(x: (x + 1 * s) * u, y: (y + 1.2 * s) * u))
    c.saveGState(); c.addPath(bowl); c.clip()
    let clay = CGGradient(colorsSpace: nil, colors: [rgb(0.86, 0.42, 0.18), rgb(0.5, 0.17, 0.06)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(clay, start: CGPoint(x: x * u, y: y * u), end: CGPoint(x: x * u, y: (y + 5 * s) * u), options: [])
    c.restoreGState()
    c.setFillColor(gold)
    for i in 0..<5 { c.fillEllipse(in: CGRect(x: (x - 4 * s + CGFloat(i) * 2 * s) * u, y: (y + 1.8 * s) * u, width: 0.7 * s * u, height: 0.7 * s * u)) }
    let flame = CGMutablePath()
    let fx = x + 4.5 * s, fy = y - 1.2 * s
    flame.move(to: CGPoint(x: fx * u, y: (fy - 6.5 * s) * u))
    flame.addCurve(to: CGPoint(x: fx * u, y: fy * u), control1: CGPoint(x: (fx + 3 * s) * u, y: (fy - 3 * s) * u), control2: CGPoint(x: (fx + 2.2 * s) * u, y: fy * u))
    flame.addCurve(to: CGPoint(x: fx * u, y: (fy - 6.5 * s) * u), control1: CGPoint(x: (fx - 2.2 * s) * u, y: fy * u), control2: CGPoint(x: (fx - 3 * s) * u, y: (fy - 3 * s) * u))
    c.saveGState(); c.setShadow(offset: .zero, blur: 4 * s * u, color: rgb(1, 0.6, 0.1)); c.setFillColor(rgb(1, 0.55, 0.1)); c.addPath(flame); c.fillPath(); c.restoreGState()
    c.saveGState()
    c.translateBy(x: fx * u, y: (fy - 1.2 * s) * u); c.scaleBy(x: 0.5, y: 0.6); c.translateBy(x: -fx * u, y: -(fy - 1.2 * s) * u)
    c.setFillColor(rgb(1, 0.95, 0.7)); c.addPath(flame); c.fillPath()
    c.restoreGState()
}

/// A glass bauble on a thread from the top edge.
func ornament(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor, from top: CGFloat = 0) {
    c.setStrokeColor(rgb(1, 0.85, 0.5, 0.7)); c.setLineWidth(0.4 * u)
    c.move(to: CGPoint(x: x * u, y: top * u)); c.addLine(to: CGPoint(x: x * u, y: (y - r) * u)); c.strokePath()
    c.setFillColor(gold); c.fill(CGRect(x: (x - r * 0.3) * u, y: (y - r - 1) * u, width: r * 0.6 * u, height: 1.4 * u))
    let comps = color.components!
    let light = rgb(min(comps[0] + 0.4, 1), min(comps[1] + 0.4, 1), min(comps[2] + 0.4, 1))
    let g = CGGradient(colorsSpace: nil, colors: [light, color, rgb(comps[0] * 0.35, comps[1] * 0.35, comps[2] * 0.35)] as CFArray, locations: [0, 0.5, 1])!
    c.saveGState(); c.addEllipse(in: CGRect(x: (x - r) * u, y: (y - r) * u, width: 2 * r * u, height: 2 * r * u)); c.clip()
    c.drawRadialGradient(g, startCenter: CGPoint(x: (x - r * 0.35) * u, y: (y - r * 0.35) * u), startRadius: 0, endCenter: CGPoint(x: x * u, y: y * u), endRadius: r * 1.1 * u, options: [])
    c.setStrokeColor(rgb(1, 1, 1, 0.25)); c.setLineWidth(0.35 * u)
    c.move(to: CGPoint(x: (x - r) * u, y: y * u)); c.addQuadCurve(to: CGPoint(x: (x + r) * u, y: y * u), control: CGPoint(x: x * u, y: (y + r * 0.5) * u)); c.strokePath()
    c.restoreGState()
    c.setFillColor(rgb(1, 1, 1, 0.75)); c.fillEllipse(in: CGRect(x: (x - r * 0.55) * u, y: (y - r * 0.6) * u, width: r * 0.4 * u, height: r * 0.28 * u))
}

/// A sagging string of fairy lights between two points, bulbs glowing in turn.
func lights(_ c: CGContext, _ u: CGFloat, from a: CGPoint, to b: CGPoint, sag: CGFloat, bulbs: Int, colors: [CGColor]) {
    let ctrl = CGPoint(x: (a.x + b.x) / 2, y: max(a.y, b.y) + sag)
    func at(_ t: CGFloat) -> CGPoint {
        let m = 1 - t
        return CGPoint(x: m * m * a.x + 2 * m * t * ctrl.x + t * t * b.x, y: m * m * a.y + 2 * m * t * ctrl.y + t * t * b.y)
    }
    c.setStrokeColor(rgb(0.15, 0.25, 0.15)); c.setLineWidth(0.5 * u)
    c.move(to: CGPoint(x: a.x * u, y: a.y * u)); c.addQuadCurve(to: CGPoint(x: b.x * u, y: b.y * u), control: CGPoint(x: ctrl.x * u, y: ctrl.y * u)); c.strokePath()
    for i in 0..<bulbs {
        let p = at((CGFloat(i) + 0.5) / CGFloat(bulbs)), color = colors[i % colors.count]
        soft(c, u, x: p.x, y: p.y + 1.6, r: 4, color: color.copy(alpha: 0.45)!)
        c.saveGState(); c.setShadow(offset: .zero, blur: 2 * u, color: color); c.setFillColor(color)
        c.fillEllipse(in: CGRect(x: (p.x - 0.9) * u, y: (p.y + 0.5) * u, width: 1.8 * u, height: 2.6 * u)); c.restoreGState()
    }
}

/// A powder cloud: overlapping soft puffs plus a spray of sharp droplets flung outward.
func powder(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor, seed: UInt64, drops: Int = 14) {
    var rnd = Scatter(seed: seed)
    for _ in 0..<12 {
        soft(c, u, x: x + (rnd.next() - 0.5) * r, y: y + (rnd.next() - 0.5) * r, r: r * (0.35 + rnd.next() * 0.4), color: color.copy(alpha: 0.55)!)
    }
    soft(c, u, x: x, y: y, r: r * 0.45, color: color)
    c.setFillColor(color)
    for _ in 0..<drops {
        let a = rnd.next() * 2 * .pi, d = r * (0.6 + rnd.next() * 0.8), s = 0.4 + rnd.next() * 1.3
        c.fillEllipse(in: CGRect(x: (x + cos(a) * d - s / 2) * u, y: (y + sin(a) * d - s / 2) * u, width: s * u, height: s * u))
    }
}

/// A Chinese lantern on a cord: ribbed red body, gold caps, a tassel.
func lantern(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, w: CGFloat) {
    let h = w * 0.85
    c.setStrokeColor(gold); c.setLineWidth(0.4 * u)
    c.move(to: CGPoint(x: x * u, y: 0)); c.addLine(to: CGPoint(x: x * u, y: (y - h / 2) * u)); c.strokePath()
    soft(c, u, x: x, y: y, r: w * 1.1, color: rgb(1, 0.35, 0.15, 0.5))
    let body = CGRect(x: (x - w / 2) * u, y: (y - h / 2) * u, width: w * u, height: h * u)
    c.saveGState(); c.addEllipse(in: body); c.clip()
    let g = CGGradient(colorsSpace: nil, colors: [rgb(1, 0.55, 0.25), rgb(0.85, 0.1, 0.08), rgb(0.45, 0.02, 0.02)] as CFArray, locations: [0, 0.55, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: x * u, y: y * u), startRadius: 0, endCenter: CGPoint(x: x * u, y: y * u), endRadius: w * 0.6 * u, options: [])
    c.setStrokeColor(rgb(0.4, 0, 0, 0.6)); c.setLineWidth(0.35 * u)
    for k in [-0.3, 0.0, 0.3] as [CGFloat] {
        c.move(to: CGPoint(x: (x + k * w) * u, y: (y - h / 2) * u))
        c.addQuadCurve(to: CGPoint(x: (x + k * w) * u, y: (y + h / 2) * u), control: CGPoint(x: (x + k * w * 1.9) * u, y: y * u))
    }
    c.strokePath(); c.restoreGState()
    c.setFillColor(gold)
    c.fill(CGRect(x: (x - w * 0.28) * u, y: (y - h / 2 - 1) * u, width: w * 0.56 * u, height: 1.6 * u))
    c.fill(CGRect(x: (x - w * 0.28) * u, y: (y + h / 2 - 0.6) * u, width: w * 0.56 * u, height: 1.6 * u))
    c.setStrokeColor(gold); c.setLineWidth(0.35 * u)
    for k in -2...2 {
        c.move(to: CGPoint(x: (x + CGFloat(k) * 0.5) * u, y: (y + h / 2 + 1) * u)); c.addLine(to: CGPoint(x: (x + CGFloat(k) * 0.7) * u, y: (y + h / 2 + 5) * u))
    }
    c.strokePath()
}

/// A plum blossom: five round pink petals around a gold heart.
func blossom(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat) {
    c.setFillColor(rgb(1, 0.72, 0.8))
    for i in 0..<5 {
        let a = CGFloat(i) / 5 * 2 * .pi - .pi / 2
        c.fillEllipse(in: CGRect(x: (x + cos(a) * r * 0.55 - r * 0.45) * u, y: (y + sin(a) * r * 0.55 - r * 0.45) * u, width: r * 0.9 * u, height: r * 0.9 * u))
    }
    c.setFillColor(gold); c.fillEllipse(in: CGRect(x: (x - r * 0.22) * u, y: (y - r * 0.22) * u, width: r * 0.44 * u, height: r * 0.44 * u))
}

/// The eight-pointed star (two overlapping squares) from Islamic geometric patterns.
func rubElHizb(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, r: CGFloat, color: CGColor, width: CGFloat = 0.35) {
    c.setStrokeColor(color); c.setLineWidth(width * u)
    for rot in [0, CGFloat.pi / 4] {
        c.saveGState(); c.translateBy(x: x * u, y: y * u); c.rotate(by: rot)
        c.stroke(CGRect(x: -r * 0.7 * u, y: -r * 0.7 * u, width: r * 1.4 * u, height: r * 1.4 * u)); c.restoreGState()
    }
}

/// A fanous lantern hanging on a chain, its windows lit.
func fanous(_ c: CGContext, _ u: CGFloat, x: CGFloat, y: CGFloat, s: CGFloat) {
    c.setStrokeColor(gold); c.setLineWidth(0.35 * u)
    c.move(to: CGPoint(x: x * u, y: 0)); c.addLine(to: CGPoint(x: x * u, y: (y - 6 * s) * u)); c.strokePath()
    soft(c, u, x: x, y: y, r: 9 * s, color: rgb(1, 0.75, 0.3, 0.5))
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x * u, y: (y - 6 * s) * u))
    p.addLine(to: CGPoint(x: (x + 2.6 * s) * u, y: (y - 3 * s) * u)); p.addLine(to: CGPoint(x: (x + 2.6 * s) * u, y: (y + 2.5 * s) * u))
    p.addLine(to: CGPoint(x: x * u, y: (y + 5.5 * s) * u)); p.addLine(to: CGPoint(x: (x - 2.6 * s) * u, y: (y + 2.5 * s) * u))
    p.addLine(to: CGPoint(x: (x - 2.6 * s) * u, y: (y - 3 * s) * u)); p.closeSubpath()
    c.setFillColor(rgb(0.85, 0.62, 0.25)); c.addPath(p); c.fillPath()
    c.saveGState(); c.setShadow(offset: .zero, blur: 3 * s * u, color: rgb(1, 0.85, 0.4))
    c.setFillColor(rgb(1, 0.93, 0.62))
    c.fill(CGRect(x: (x - 1.8 * s) * u, y: (y - 2.4 * s) * u, width: 1.5 * s * u, height: 4.3 * s * u))
    c.fill(CGRect(x: (x + 0.3 * s) * u, y: (y - 2.4 * s) * u, width: 1.5 * s * u, height: 4.3 * s * u))
    c.restoreGState()
}

/// A mosque skyline: central dome, two side domes, two minarets.
func mosque(_ c: CGContext, _ u: CGFloat, base: CGFloat, color: CGColor) {
    let p = CGMutablePath()
    func dome(_ cx: CGFloat, _ w: CGFloat, _ top: CGFloat) {
        p.addRect(CGRect(x: (cx - w / 2) * u, y: top * u, width: w * u, height: (base - top) * u))
        p.move(to: CGPoint(x: (cx - w / 2) * u, y: top * u))
        p.addCurve(to: CGPoint(x: cx * u, y: (top - w * 0.85) * u), control1: CGPoint(x: (cx - w / 2) * u, y: (top - w * 0.55) * u), control2: CGPoint(x: (cx - w * 0.1) * u, y: (top - w * 0.6) * u))
        p.addCurve(to: CGPoint(x: (cx + w / 2) * u, y: top * u), control1: CGPoint(x: (cx + w * 0.1) * u, y: (top - w * 0.6) * u), control2: CGPoint(x: (cx + w / 2) * u, y: (top - w * 0.55) * u))
        p.closeSubpath()
    }
    func minaret(_ cx: CGFloat, _ top: CGFloat) {
        p.addRect(CGRect(x: (cx - 1.4) * u, y: top * u, width: 2.8 * u, height: (base - top) * u))
        p.addRect(CGRect(x: (cx - 2.2) * u, y: (top + 4) * u, width: 4.4 * u, height: 1.2 * u))
        p.move(to: CGPoint(x: (cx - 1.4) * u, y: top * u)); p.addLine(to: CGPoint(x: cx * u, y: (top - 4) * u)); p.addLine(to: CGPoint(x: (cx + 1.4) * u, y: top * u)); p.closeSubpath()
    }
    dome(50, 22, 90); dome(33, 11, 93); dome(67, 11, 93); minaret(18, 80); minaret(82, 80)
    p.addRect(CGRect(x: 0, y: base * u, width: 100 * u, height: (100 - base) * u))
    c.setFillColor(color); c.addPath(p); c.fillPath()
}

let holidays = [
    Stock(name: "AppIcon-Christmas", light: rgb(1, 0.42, 0.37), base: rgb(0.78, 0.13, 0.11), glow: rgb(1, 0.3, 0.25, 0.25), ink: cream,
          back: { c, u in
              dots(c, u, seed: 12, count: 60, colors: [rgb(1, 1, 1, 0.8), rgb(1, 1, 1, 0.45)], size: 0.7...2.2)
              lights(c, u, from: CGPoint(x: -4, y: 6), to: CGPoint(x: 104, y: 8), sag: 9, bulbs: 9, colors: [rgb(1, 0.25, 0.2), rgb(1, 0.82, 0.3), rgb(0.3, 0.85, 0.45), rgb(0.35, 0.6, 1)])
              ornament(c, u, x: 16, y: 21, r: 4.2, color: rgb(0.85, 0.65, 0.2), from: 10)
              ornament(c, u, x: 82, y: 19, r: 3.6, color: rgb(0.2, 0.55, 0.35), from: 11)
              ornament(c, u, x: 50, y: 20, r: 3.2, color: rgb(0.85, 0.12, 0.15), from: 14)
              // A snowdrift along the bottom.
              let drift = CGMutablePath()
              drift.move(to: CGPoint(x: 0, y: 90 * u))
              drift.addCurve(to: CGPoint(x: 100 * u, y: 86 * u), control1: CGPoint(x: 30 * u, y: 82 * u), control2: CGPoint(x: 62 * u, y: 94 * u))
              drift.addLine(to: CGPoint(x: 100 * u, y: 100 * u)); drift.addLine(to: CGPoint(x: 0, y: 100 * u)); drift.closeSubpath()
              c.saveGState(); c.addPath(drift); c.clip()
              let snow = CGGradient(colorsSpace: nil, colors: [rgb(0.92, 0.95, 1), rgb(0.62, 0.7, 0.85)] as CFArray, locations: [0, 1])!
              c.drawLinearGradient(snow, start: CGPoint(x: 0, y: 84 * u), end: CGPoint(x: 0, y: 100 * u), options: [])
              c.restoreGState()
          },
          front: { c, u in
              // Snow settled on the ticket's top edge.
              c.saveGState(); c.translateBy(x: 50 * u, y: 50 * u); c.rotate(by: -14 * .pi / 180); c.translateBy(x: -50 * u, y: -50 * u)
              let cap = CGMutablePath()
              cap.move(to: CGPoint(x: 15 * u, y: 31.6 * u))
              var x: CGFloat = 15
              for (w, h) in [(7.0, 2.6), (9, 3.4), (6, 2.2), (8, 3), (7, 2.4), (6, 1.6)] as [(CGFloat, CGFloat)] {
                  cap.addQuadCurve(to: CGPoint(x: (x + w) * u, y: 31.6 * u), control: CGPoint(x: (x + w / 2) * u, y: (31.6 - h * 2) * u))
                  x += w
              }
              cap.addLine(to: CGPoint(x: x * u, y: 32.4 * u)); cap.addLine(to: CGPoint(x: 15 * u, y: 32.4 * u)); cap.closeSubpath()
              c.setFillColor(rgb(0.96, 0.98, 1)); c.addPath(cap); c.fillPath()
              c.restoreGState()
          }),
    Stock(name: "AppIcon-Diwali", light: rgb(1, 0.88, 0.54), base: rgb(0.91, 0.64, 0.09), glow: rgb(0.85, 0.2, 0.55, 0.38), ink: rgb(0.23, 0.04, 0.07),
          back: { c, u in
              firework(c, u, x: 20, y: 17, r: 15, colors: [rgb(1, 0.8, 0.3), rgb(1, 0.5, 0.2)], seed: 1)
              firework(c, u, x: 80, y: 13, r: 12, colors: [rgb(1, 0.4, 0.75), rgb(1, 0.85, 0.5)], seed: 2)
              firework(c, u, x: 55, y: 8, r: 6, colors: [rgb(0.6, 0.9, 1)], rays: 12, seed: 3)
              dots(c, u, seed: 7, count: 18, colors: [rgb(1, 0.8, 0.4)], size: 0.5...1.2, glow: true)
              diya(c, u, x: 18, y: 91, s: 1.05); diya(c, u, x: 48, y: 94, s: 0.9); diya(c, u, x: 78, y: 90, s: 1.05)
          }),
    Stock(name: "AppIcon-Holi", light: rgb(1, 1, 1), base: rgb(0.93, 0.93, 0.94), glow: rgb(1, 0.3, 0.7, 0.22), ink: rgb(0.1, 0.1, 0.12),
          back: { c, u in
              powder(c, u, x: 14, y: 16, r: 20, color: rgb(1, 0.15, 0.55), seed: 1)
              powder(c, u, x: 86, y: 14, r: 17, color: rgb(1, 0.82, 0.05), seed: 2)
              powder(c, u, x: 16, y: 88, r: 18, color: rgb(0.15, 0.78, 0.35), seed: 3)
              powder(c, u, x: 86, y: 86, r: 19, color: rgb(0.15, 0.45, 1), seed: 4)
              powder(c, u, x: 52, y: 6, r: 9, color: rgb(1, 0.5, 0.1), seed: 5)
              powder(c, u, x: 50, y: 95, r: 10, color: rgb(0.6, 0.25, 1), seed: 6)
          },
          front: { c, u in
              powder(c, u, x: 24, y: 64, r: 8, color: rgb(1, 0.15, 0.55, 0.75), seed: 7, drops: 8)
              powder(c, u, x: 74, y: 34, r: 7, color: rgb(1, 0.82, 0.05, 0.75), seed: 8, drops: 8)
              powder(c, u, x: 58, y: 68, r: 5, color: rgb(0.15, 0.45, 1, 0.6), seed: 9, drops: 6)
          }),
    Stock(name: "AppIcon-Easter", light: rgb(0.92, 0.86, 1), base: rgb(0.72, 0.62, 0.95), glow: rgb(0.7, 0.9, 0.8, 0.22), ink: rgb(0.23, 0.16, 0.4),
          back: { c, u in
              let eggs: [(CGFloat, CGFloat, CGFloat, CGColor)] = [(14, 84, -0.3, rgb(0.6, 0.9, 0.78)), (26, 90, 0.2, rgb(1, 0.78, 0.86)), (80, 16, 0.3, rgb(1, 0.93, 0.6)), (90, 26, -0.2, rgb(0.62, 0.85, 1))]
              for (x, y, a, color) in eggs {
                  c.saveGState(); c.translateBy(x: x * u, y: y * u); c.rotate(by: a)
                  c.setFillColor(color); c.fillEllipse(in: CGRect(x: -5 * u, y: -7 * u, width: 10 * u, height: 14 * u)); c.restoreGState()
              }
          }),
    Stock(name: "AppIcon-July4", light: rgb(0.36, 0.52, 0.9), base: rgb(0.11, 0.2, 0.48), glow: rgb(0.9, 0.2, 0.25, 0.25), ink: rgb(1, 1, 1),
          back: { c, u in
              firework(c, u, x: 22, y: 18, r: 17, colors: [rgb(1, 0.25, 0.25), rgb(1, 0.6, 0.55)], rays: 20, seed: 11)
              firework(c, u, x: 78, y: 14, r: 13, colors: [rgb(1, 1, 1), rgb(0.85, 0.9, 1)], seed: 12)
              firework(c, u, x: 80, y: 86, r: 14, colors: [rgb(0.35, 0.55, 1), rgb(0.7, 0.8, 1)], seed: 13)
              firework(c, u, x: 20, y: 88, r: 9, colors: [rgb(1, 1, 1), rgb(1, 0.3, 0.3)], rays: 14, seed: 14)
              for (x, y) in [(50.0, 9.0), (8, 50), (93, 52), (52, 94)] as [(CGFloat, CGFloat)] { star(c, u, x: x, y: y, r: 1.6, color: rgb(1, 1, 1, 0.8)) }
          }),
    Stock(name: "AppIcon-NewYear", light: rgb(1, 0.95, 0.84), base: rgb(0.85, 0.71, 0.42), glow: rgb(1, 0.85, 0.5, 0.25), ink: rgb(0, 0, 0),
          back: { c, u in
              firework(c, u, x: 22, y: 17, r: 17, colors: [gold, rgb(1, 0.95, 0.75)], rays: 22, seed: 21)
              firework(c, u, x: 80, y: 15, r: 14, colors: [rgb(0.85, 0.9, 1), rgb(1, 1, 1)], rays: 20, seed: 22)
              firework(c, u, x: 82, y: 86, r: 11, colors: [rgb(1, 0.5, 0.75), gold], seed: 23)
              firework(c, u, x: 52, y: 6, r: 6, colors: [gold], rays: 12, seed: 24)
              var r = Scatter(seed: 99)
              for i in 0..<26 {
                  c.saveGState(); c.translateBy(x: r.next() * 100 * u, y: (60 + r.next() * 40) * u); c.rotate(by: r.next() * .pi)
                  c.setFillColor([gold, rgb(0.85, 0.87, 0.92), rgb(1, 0.6, 0.4), rgb(1, 1, 1)][i % 4])
                  c.fill(CGRect(x: -1.2 * u, y: -0.5 * u, width: 2.4 * u, height: 1 * u)); c.restoreGState()
              }
          }),
    Stock(name: "AppIcon-LunarNewYear", light: rgb(1, 0.4, 0.32), base: rgb(0.77, 0.09, 0.11), glow: rgb(1, 0.75, 0.3, 0.28), ink: gold,
          back: { c, u in
              lantern(c, u, x: 16, y: 16, w: 13); lantern(c, u, x: 84, y: 12, w: 10)
              // A plum blossom branch climbing in from the bottom-left corner.
              c.setStrokeColor(rgb(0.35, 0.2, 0.12)); c.setLineWidth(1.4 * u); c.setLineCap(.round)
              c.move(to: CGPoint(x: -2 * u, y: 100 * u)); c.addCurve(to: CGPoint(x: 40 * u, y: 86 * u), control1: CGPoint(x: 12 * u, y: 86 * u), control2: CGPoint(x: 26 * u, y: 94 * u)); c.strokePath()
              c.setLineWidth(0.8 * u); c.move(to: CGPoint(x: 16 * u, y: 92 * u)); c.addLine(to: CGPoint(x: 20 * u, y: 80 * u)); c.strokePath()
              for (x, y, r) in [(20.0, 80.0, 3.4), (40, 86, 3), (30, 90, 2.6), (10, 93, 2.4), (25, 84, 1.8)] as [(CGFloat, CGFloat, CGFloat)] { blossom(c, u, x: x, y: y, r: r) }
              // 福 (good fortune) on a red diamond, bottom right.
              c.saveGState(); c.translateBy(x: 82 * u, y: 86 * u); c.rotate(by: .pi / 4)
              c.setFillColor(rgb(0.85, 0.08, 0.1)); c.fill(CGRect(x: -7 * u, y: -7 * u, width: 14 * u, height: 14 * u))
              c.setStrokeColor(gold); c.setLineWidth(0.5 * u); c.stroke(CGRect(x: -6 * u, y: -6 * u, width: 12 * u, height: 12 * u))
              c.restoreGState()
              let fu = NSAttributedString(string: "福", attributes: [.font: NSFont.systemFont(ofSize: 11 * u, weight: .heavy), .foregroundColor: NSColor(cgColor: gold)!])
              let line = CTLineCreateWithAttributedString(fu), b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
              c.saveGState(); c.translateBy(x: 82 * u - b.midX, y: 86 * u + b.midY); c.scaleBy(x: 1, y: -1); c.textPosition = .zero; CTLineDraw(line, c); c.restoreGState()
              dots(c, u, seed: 5, count: 14, colors: [gold], size: 0.6...1.4, glow: true)
          }),
    Stock(name: "AppIcon-Eid", light: rgb(0.4, 0.82, 0.66), base: rgb(0.07, 0.48, 0.36), glow: rgb(0.3, 0.8, 0.6, 0.22), ink: cream,
          back: { c, u in
              // Faint geometric stars tiled across the night.
              for y in stride(from: CGFloat(10), to: 80, by: 20) {
                  for x in stride(from: CGFloat(y.truncatingRemainder(dividingBy: 40) == 10 ? 10 : 20), to: 100, by: 20) {
                      rubElHizb(c, u, x: x, y: y, r: 6, color: rgb(1, 0.85, 0.5, 0.12))
                  }
              }
              let moon = CGMutablePath()
              moon.addEllipse(in: CGRect(x: 40 * u, y: 3 * u, width: 18 * u, height: 18 * u))
              let cut = CGMutablePath()
              cut.addEllipse(in: CGRect(x: 45.5 * u, y: 0.5 * u, width: 16 * u, height: 16 * u))
              soft(c, u, x: 49, y: 12, r: 14, color: rgb(1, 0.85, 0.5, 0.35))
              c.saveGState(); c.setShadow(offset: .zero, blur: 3 * u, color: gold); c.setFillColor(gold); c.addPath(moon.subtracting(cut)); c.fillPath(); c.restoreGState()
              star(c, u, x: 60, y: 9, r: 2.4, color: gold)
              fanous(c, u, x: 14, y: 16, s: 1.1); fanous(c, u, x: 86, y: 12, s: 0.95)
              soft(c, u, x: 50, y: 98, r: 48, color: rgb(1, 0.72, 0.32, 0.5))
              mosque(c, u, base: 96, color: rgb(0.03, 0.2, 0.15))
          }),
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
    stock.back?(ctx, u)

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
    stock.front?(ctx, u)
    return ctx.makeImage()!
}

func png(_ image: CGImage) -> Data { NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])! }

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("SceneStash/Resources/Assets.xcassets")
let fm = FileManager.default
for stock in stocks + holidays {
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
print("wrote \(stocks.count + holidays.count) icons")
