import CoreImage
import UIKit

/// Loads TMDB images with a memory cache on top of URLCache's disk cache.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let tints = NSCache<NSURL, UIColor>()
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    let glowContext = CIContext()
    let glowCache = NSCache<NSURL, UIImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 << 20, diskCapacity: 400 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard let (data, _) = try? await session.data(from: url),
              let image = await UIImage(data: data)?.byPreparingForDisplay() else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// The poster's average colour, pushed toward a usable accent: saturated and bright enough to read on ink.
    func tint(for url: URL) async -> UIColor? {
        if let hit = tints.object(forKey: url as NSURL) { return hit }
        guard let image = await image(url), let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        // Near-greyscale posters have no colour worth borrowing; keep the signature amber.
        let tint = s < 0.18 ? Theme.accent : UIColor(hue: h, saturation: min(max(s * 1.5, 0.5), 0.85), brightness: max(b, 0.9), alpha: 1)
        tints.setObject(tint, forKey: url as NSURL)
        return tint
    }
}

extension UIImageView {
    private static var taskKey: UInt8 = 0

    /// Sets a remote image with a quick fade, cancelling any previous load for this view (safe for reused cells).
    func setImage(_ url: URL?, placeholder: UIImage? = nil) {
        (objc_getAssociatedObject(self, &Self.taskKey) as? Task<Void, Never>)?.cancel()
        guard let url else { image = placeholder; return }
        if let hit = ImageLoader.shared.cached(url) { image = hit; return }
        image = placeholder
        let task = Task { [weak self] in
            guard let image = await ImageLoader.shared.image(url), !Task.isCancelled, let self else { return }
            UIView.transition(with: self, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.image = image
            }
        }
        objc_setAssociatedObject(self, &Self.taskKey, task, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
