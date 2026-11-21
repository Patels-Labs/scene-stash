import ActivityKit
import AppIntents
import Foundation

// Compiled into both the app and the widget extension.

nonisolated enum SharedBox {
    static let group = "group.com.heetpatel.scenestash"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    /// Small poster thumbnails the app saves for the Live Activity and widgets, which can't fetch images themselves.
    static func posterURL(_ id: Int) -> URL? { container?.appendingPathComponent("poster-\(id).jpg") }
    /// The Live Activity's own, smaller copy: it draws a grey box for an image much bigger than it shows, and
    /// Tonight rewrites `posterURL` at hero size.
    static func livePosterURL(_ id: Int) -> URL? { container?.appendingPathComponent("live-poster-\(id).jpg") }
}

// MARK: - Widgets

/// What the widgets show, written by the app whenever Tonight refreshes.
nonisolated struct WidgetSnapshot: Codable, Sendable {
    // type: "movie" or "tv", for the link back into the app; nil in snapshots saved before links.
    struct Slot: Codable, Sendable { let id: Int; var type: String? = nil; let name: String; let code: String; let start: Date; let tint: String }
    struct Premiere: Codable, Sendable { let id: Int; var type: String? = nil; let name: String; let label: String; let date: Date }
    struct Card: Codable, Sendable { let id: Int; let name: String; let season: Int; let holes: [Int]; let left: Int } // holes: 0 todo, 1 watched, 2 next

    var unlocked = false
    var doors: Date?
    var booked = 0
    var programme: [Slot] = []
    var premiere: Premiere?
    var card: Card?

    static let key = "widgetSnapshot"
    static func load() -> WidgetSnapshot {
        SharedBox.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) } ?? WidgetSnapshot()
    }
    func save() { SharedBox.defaults.set(try? JSONEncoder().encode(self), forKey: Self.key) }

    /// scenestash://title/tv/95396?name=Severance — tapping a widget opens that title's page.
    static func link(_ id: Int, _ type: String?, _ name: String) -> URL? {
        guard let type else { return nil }
        var c = URLComponents(string: "scenestash://title/\(type)/\(id)")
        c?.queryItems = [URLQueryItem(name: "name", value: name)]
        return c?.url
    }
}

// MARK: - Now showing

/// The app installs these at launch; Live Activity buttons run their intents in the app's process.
@MainActor enum WatchHooks {
    static var pause: (() async -> Void)?
    static var resume: (() async -> Void)?
    static var finish: (() async -> Void)?

    static func runPause() async { await pause?() }
    static func runResume() async { await resume?() }
    static func runFinish() async { await finish?() }
}

#if !targetEnvironment(macCatalyst) // Live Activities are iPhone-only.
nonisolated struct NowShowingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// When the film would have started if it had never been paused; elapsed time is `now - startedAt`.
        var startedAt: Date
        var pausedAt: Date?
        var finished = false

        func elapsed(at now: Date = .now) -> TimeInterval { (pausedAt ?? now).timeIntervalSince(startedAt) }
    }

    let id: Int
    let name: String
    let runtimeMinutes: Int
    let tint: String
    /// Scenes during or after the credits, so the activity can say "stay seated" at the end.
    let stinger: Bool

    func end(_ state: ContentState) -> Date { state.startedAt.addingTimeInterval(TimeInterval(runtimeMinutes * 60)) }
}

nonisolated struct PauseWatchingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause"
    init() {}
    func perform() async throws -> some IntentResult {
        await WatchHooks.runPause()
        return .result()
    }
}

nonisolated struct ResumeWatchingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume"
    init() {}
    func perform() async throws -> some IntentResult {
        await WatchHooks.runResume()
        return .result()
    }
}

nonisolated struct FinishWatchingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finished"
    init() {}
    func perform() async throws -> some IntentResult {
        await WatchHooks.runFinish()
        return .result()
    }
}
#endif
