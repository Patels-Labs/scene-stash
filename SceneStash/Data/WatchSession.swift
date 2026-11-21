import ActivityKit
import UIKit
import WidgetKit

extension Notification.Name {
    static let watchChanged = Notification.Name("watchChanged")
}

/// "Start now": keeps time against what you're actually watching, with a Live Activity on the Lock Screen and in
/// the Dynamic Island. Pause for ads or a break and the end time moves with you. Your place is saved to the film
/// as you go, so the strip on its page and Tonight stay right.
final class WatchSession {
    static let shared = WatchSession()

    struct State: Codable {
        let id: Int
        let name: String
        let poster: String?
        let backdrop: String?
        let runtime: Int
        let stinger: Bool
        let tint: String
        var startedAt: Date
        var pausedAt: Date?
        /// Set when this is an episode; `id` and `name` are then the show's.
        var season: Int?
        var episode: Int?

        var key: EpisodeKey? { season.flatMap { s in episode.map { EpisodeKey(season: s, episode: $0) } } }
        var elapsed: TimeInterval { (pausedAt ?? .now).timeIntervalSince(startedAt) }
        var title: Title { Title(id: id, mediaType: season == nil ? .movie : .tv, name: name, posterPath: poster, backdropPath: backdrop) }
        #if !targetEnvironment(macCatalyst)
        var content: NowShowingAttributes.ContentState { .init(startedAt: startedAt, pausedAt: pausedAt) }
        #endif
    }

    private static let key = "watchSession"
    private(set) var state: State? {
        didSet {
            SharedBox.defaults.set(state.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key)
            NotificationCenter.default.post(name: .watchChanged, object: nil)
        }
    }

    private init() {
        state = SharedBox.defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
    }

    func isWatching(_ id: Int) -> Bool { state?.id == id }

    /// Wires the Live Activity's buttons to this session.
    func installHooks() {
        WatchHooks.pause = { [weak self] in await self?.pause() }
        WatchHooks.resume = { [weak self] in await self?.resume() }
        WatchHooks.finish = { [weak self] in await self?.finish() }
    }

    func start(_ title: Title, runtime: Int, from seconds: Int, stinger: Bool, episode: EpisodeKey? = nil) async {
        // Nothing to keep time against before it's out.
        if episode == nil, title.unreleased { return }
        await stop()
        var tint = "F5B544"
        if let url = TMDB.imageURL(title.posterPath, .poster) {
            if let color = await ImageLoader.shared.tint(for: url) { tint = color.hex }
            await savePoster(url, id: title.id)
        }
        state = State(id: title.id, name: title.name, poster: title.posterPath, backdrop: title.backdropPath, runtime: runtime,
                      stinger: stinger, tint: tint, startedAt: Date.now.addingTimeInterval(-TimeInterval(seconds)), pausedAt: nil,
                      season: episode?.season, episode: episode?.episode)
        Store.shared.setPosition(max(seconds, 1), for: title, runtime: runtime)
        Haptics.thunk()
        #if !targetEnvironment(macCatalyst) // Live Activities are iPhone-only; the Mac preview just keeps time.
        guard let state, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = NowShowingAttributes(id: state.id, name: episode.map { "\(state.name) · S\($0.season), E\($0.episode)" } ?? state.name, runtimeMinutes: runtime, tint: tint, stinger: stinger)
        _ = try? Activity.request(attributes: attributes, content: .init(state: state.content, staleDate: attributes.end(state.content).addingTimeInterval(3600)))
        #endif
    }

    func pause() async {
        guard var s = state, s.pausedAt == nil else { return }
        s.pausedAt = .now
        state = s
        savePosition()
        await update()
    }

    func resume() async {
        guard var s = state, let paused = s.pausedAt else { return }
        s.startedAt = s.startedAt.addingTimeInterval(Date.now.timeIntervalSince(paused))
        s.pausedAt = nil
        state = s
        await update()
    }

    /// Jumps the clock to `seconds` in, playing or paused: skipping a recap, or catching up after one.
    func seek(to seconds: Int) async {
        guard var s = state else { return }
        s.startedAt = (s.pausedAt ?? .now).addingTimeInterval(-TimeInterval(seconds))
        state = s
        savePosition()
        await update()
    }

    /// Marks the film or episode seen and lets the activity show a last "finished" frame before it goes.
    func finish() async {
        guard let s = state else { return }
        state = nil
        if let key = s.key {
            Store.shared.setWatched([key], watched: true, show: s.title, runtime: s.runtime)
        } else {
            Store.shared.track(s.title, status: .seen, runtime: s.runtime)
        }
        Haptics.success()
        #if !targetEnvironment(macCatalyst)
        var final = s.content
        final.finished = true
        for activity in Activity<NowShowingAttributes>.activities {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(10 * 60)))
        }
        #endif
    }

    /// Ends tracking without marking anything: another film started, or it left Watching (then `saving` is
    /// false, so the place isn't written back and the film doesn't slip back into Watching).
    func stop(saving: Bool = true) async {
        if saving { savePosition() }
        #if !targetEnvironment(macCatalyst)
        for activity in Activity<NowShowingAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
        state = nil
    }

    /// Saves how far in you are to the film itself. Called on pause and whenever the app comes forward.
    func savePosition() {
        guard let s = state else { return }
        let seconds = min(Int(s.elapsed), s.runtime * 60 - 60)
        Store.shared.setPosition(max(seconds, 1), for: s.title, runtime: s.runtime)
    }

    private func update() async {
        #if !targetEnvironment(macCatalyst)
        guard let s = state else { return }
        for activity in Activity<NowShowingAttributes>.activities {
            await activity.update(.init(state: s.content, staleDate: nil))
        }
        #endif
    }

    /// Saves a poster where the Live Activity and widgets can read it, `width` pixels across. WidgetKit won't
    /// draw a widget holding too large an image: it leaves the grey placeholder up instead.
    func savePoster(_ url: URL, id: Int, width: CGFloat = 360) async {
        guard let image = await ImageLoader.shared.image(url), let file = SharedBox.posterURL(id) else { return }
        let size = CGSize(width: width, height: width * 1.5)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? thumb.jpegData(compressionQuality: 0.75)?.write(to: file)
    }
}

extension UIColor {
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
