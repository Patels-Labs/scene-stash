import CoreData
import UIKit

enum TrackStatus: String, CaseIterable {
    case watchlist, watching, seen

    var label: String {
        switch self {
        case .watchlist: "Watchlist"
        case .watching: "Watching"
        case .seen: "Seen"
        }
    }
    var symbol: String {
        switch self {
        case .watchlist: "bookmark.fill"
        case .watching: "play.circle.fill"
        case .seen: "checkmark.seal.fill"
        }
    }
}

@objc(Tracked)
final class Tracked: NSManagedObject {
    @NSManaged var tmdbID: Int64
    @NSManaged var mediaTypeRaw: String?
    @NSManaged var statusRaw: String?
    @NSManaged var name: String?
    @NSManaged var posterPath: String?
    @NSManaged var backdropPath: String?
    @NSManaged var releaseDate: String?
    @NSManaged var rating: Int16
    @NSManaged var runtime: Int32
    @NSManaged var addedAt: Date?
    @NSManaged var watchedAt: Date?
    /// How far into a film you are, in seconds; 0 when not started or finished.
    @NSManaged var position: Int32
    /// Your line on the film's stub in the stub book.
    @NSManaged var note: String?

    var mediaType: MediaType { MediaType(rawValue: mediaTypeRaw ?? "") ?? .movie }
    var status: TrackStatus {
        get { TrackStatus(rawValue: statusRaw ?? "") ?? .watchlist }
        set { statusRaw = newValue.rawValue }
    }
    var title: Title {
        Title(id: Int(tmdbID), mediaType: mediaType, name: name ?? "", posterPath: posterPath, backdropPath: backdropPath, date: releaseDate)
    }
}

@objc(WatchedEpisode)
final class WatchedEpisode: NSManagedObject {
    @NSManaged var showID: Int64
    @NSManaged var season: Int16
    @NSManaged var episode: Int16
    @NSManaged var runtime: Int32
    @NSManaged var watchedAt: Date?

    var key: EpisodeKey { EpisodeKey(season: Int(season), episode: Int(episode)) }
}

/// A saved marathon. Pieces and days are stored as JSON so the plan can change shape freely.
@objc(Marathon)
final class Marathon: NSManagedObject {
    @NSManaged var uuid: String?
    @NSManaged var name: String?
    @NSManaged var piecesData: Data?
    @NSManaged var daysData: Data?
    @NSManaged var breakMinutes: Int16
    @NSManaged var runOver: Bool
    @NSManaged var createdAt: Date?

    var pieces: [Piece] {
        get { piecesData.flatMap { try? JSONDecoder().decode([Piece].self, from: $0) } ?? [] }
        set { piecesData = try? JSONEncoder().encode(newValue) }
    }
    var days: [MarathonDay] {
        get { daysData.flatMap { try? JSONDecoder().decode([MarathonDay].self, from: $0) } ?? [] }
        set { daysData = try? JSONEncoder().encode(newValue) }
    }

    /// What's still to watch: films not yet seen, episodes not yet punched.
    @MainActor var remaining: [Piece] {
        pieces.filter { p in
            if p.isEpisode, let s = p.season, let e = p.episode { return !Store.shared.watched(show: p.id).contains(EpisodeKey(season: s, episode: e)) }
            return Store.shared.tracked(p.id, .movie)?.status != .seen
        }
    }

    /// The plan for what's left, from today on. Today's doors open no earlier than now.
    @MainActor func upcomingPlan(now: Date = .now) -> [(day: MarathonDay, slots: [PlannedSlot])] {
        let ahead = days.filter { $0.end > now }.map { MarathonDay(start: max($0.start, now), end: $0.end) }
        let plan = MarathonPlan.plan(remaining, days: ahead, breakMinutes: Int(breakMinutes), runOver: runOver)
        return Array(zip(ahead, plan.days)).map { ($0, $1) }
    }
}

extension Notification.Name {
    static let syncChanged = Notification.Name("syncChanged")
}

/// The user's library. Core Data mirrored to iCloud; views observe
/// `NSManagedObjectContextObjectsDidChange` on `context` to refresh.
final class Store {
    static let shared = Store()
    /// Local previews (unsigned Catalyst builds) have no iCloud entitlement and CloudKit traps without one;
    /// launch them with `-LocalStoreOnly YES`.
    static let cloudEnabled = !UserDefaults.standard.bool(forKey: "LocalStoreOnly")

    let container: NSPersistentCloudKitContainer
    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentCloudKitContainer(name: "SceneStash", managedObjectModel: Self.model)
        let description = container.persistentStoreDescriptions.first!
        description.cloudKitContainerOptions = Self.cloudEnabled ? NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.heetpatel.scenestash") : nil
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.loadPersistentStores { _, error in
            // Sync failures (no iCloud account, schema not deployed) don't fail the load; local data keeps working.
            if let error { print("Store failed to load: \(error)") }
        }
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let ended = event.endDate else { return }
            MainActor.assumeIsolated {
                Store.shared.lastSync = (ended, event.error?.localizedDescription)
                NotificationCenter.default.post(name: .syncChanged, object: nil)
            }
        }
    }

    /// The latest finished sync with iCloud and its error, if it failed. Shown in Settings.
    private(set) var lastSync: (date: Date, error: String?)?

    // MARK: Reading

    func tracked(_ id: Int, _ type: MediaType) -> Tracked? {
        let request = NSFetchRequest<Tracked>(entityName: "Tracked")
        request.predicate = NSPredicate(format: "tmdbID == %lld AND mediaTypeRaw == %@", Int64(id), type.rawValue)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func all(_ status: TrackStatus? = nil) -> [Tracked] {
        let request = NSFetchRequest<Tracked>(entityName: "Tracked")
        if let status { request.predicate = NSPredicate(format: "statusRaw == %@", status.rawValue) }
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func episodes(show: Int? = nil) -> [WatchedEpisode] {
        let request = NSFetchRequest<WatchedEpisode>(entityName: "WatchedEpisode")
        if let show { request.predicate = NSPredicate(format: "showID == %lld", Int64(show)) }
        return (try? context.fetch(request)) ?? []
    }

    func watched(show: Int) -> Set<EpisodeKey> { Set(episodes(show: show).map(\.key)) }

    /// Number of things watched per calendar day, for the year grid.
    func watchDays(calendar: Calendar = .current) -> [Date: Int] {
        let dates = all().filter { $0.status == .seen }.compactMap(\.watchedAt) + episodes().compactMap(\.watchedAt)
        return dates.reduce(into: [:]) { $0[calendar.startOfDay(for: $1), default: 0] += 1 }
    }

    struct Stats { let minutes: Int; let titles: Int; let films: Int; let episodes: Int; let streak: Int }

    func stats() -> Stats {
        let seen = all().filter { $0.status == .seen && $0.mediaType == .movie }
        let eps = episodes()
        let minutes = seen.reduce(0) { $0 + Int($1.runtime) } + eps.reduce(0) { $0 + Int($1.runtime) }
        let days = seen.compactMap(\.watchedAt) + eps.compactMap(\.watchedAt)
        return Stats(minutes: minutes, titles: all().count, films: seen.count, episodes: eps.count, streak: Progress.streak(days: days))
    }

    // MARK: Writing

    @discardableResult
    func track(_ title: Title, status: TrackStatus, runtime: Int? = nil) -> Tracked {
        let item = tracked(title.id, title.mediaType) ?? {
            let t = Tracked(context: context)
            t.tmdbID = Int64(title.id)
            t.mediaTypeRaw = title.mediaType.rawValue
            t.addedAt = .now
            return t
        }()
        item.name = title.name
        item.posterPath = title.posterPath ?? item.posterPath
        item.backdropPath = title.backdropPath ?? item.backdropPath
        item.releaseDate = title.date ?? item.releaseDate
        if let runtime { item.runtime = Int32(runtime) }
        if status == .seen && item.status != .seen { item.watchedAt = .now; item.position = 0 }
        item.status = status
        save()
        return item
    }

    func setRating(_ rating: Int, for title: Title) {
        let item = tracked(title.id, title.mediaType) ?? track(title, status: .seen)
        item.rating = Int16(rating)
        save()
    }

    /// Records where you stopped in a film; anything past the start puts it on the Watching shelf.
    func setPosition(_ seconds: Int, for title: Title, runtime: Int?) {
        let item = tracked(title.id, title.mediaType) ?? track(title, status: .watching, runtime: runtime)
        if let runtime, item.runtime == 0 { item.runtime = Int32(runtime) }
        item.position = Int32(max(seconds, 0))
        if seconds > 0, item.status != .watching { item.status = .watching }
        save()
    }

    func setNote(_ note: String?, for title: Title) {
        guard let item = tracked(title.id, title.mediaType) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = trimmed?.isEmpty == false ? trimmed : nil
        save()
    }

    func marathons() -> [Marathon] {
        let request = NSFetchRequest<Marathon>(entityName: "Marathon")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func newMarathon(name: String, pieces: [Piece], days: [MarathonDay], breakMinutes: Int, runOver: Bool) -> Marathon {
        let m = Marathon(context: context)
        m.uuid = UUID().uuidString
        m.createdAt = .now
        m.name = name
        m.pieces = pieces
        m.days = days
        m.breakMinutes = Int16(breakMinutes)
        m.runOver = runOver
        save()
        return m
    }

    /// Today's slice of whichever marathon has something planned for today.
    func marathonToday(now: Date = .now) -> (Marathon, MarathonDay, [PlannedSlot])? {
        for m in marathons() {
            if let today = m.upcomingPlan(now: now).first(where: { Calendar.current.isDate($0.day.start, inSameDayAs: now) && !$0.slots.isEmpty }) {
                return (m, today.day, today.slots)
            }
        }
        return nil
    }

    func remove(_ title: Title) {
        if let item = tracked(title.id, title.mediaType) { context.delete(item) }
        if title.mediaType == .tv { episodes(show: title.id).forEach(context.delete) }
        save()
    }

    /// Marks episodes watched (or unwatched); starts tracking the show as Watching if needed.
    func setWatched(_ keys: [EpisodeKey], watched: Bool, show: Title, runtime: Int?) {
        let existing = Dictionary(episodes(show: show.id).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for key in keys {
            if watched, existing[key] == nil {
                let e = WatchedEpisode(context: context)
                e.showID = Int64(show.id)
                e.season = Int16(key.season)
                e.episode = Int16(key.episode)
                e.runtime = Int32(runtime ?? 0)
                e.watchedAt = .now
            } else if !watched, let e = existing[key] {
                context.delete(e)
            }
        }
        if watched, tracked(show.id, .tv)?.status != .seen {
            track(show, status: .watching, runtime: runtime)
        } else {
            save()
        }
    }

    /// Titles marked seen without details (e.g. from onboarding) have no runtime; fill them in so hours add up.
    func backfillRuntimes() async {
        for item in all().filter({ $0.runtime == 0 && $0.status != .watchlist }) {
            guard let detail = try? await TMDB.shared.detail(Int(item.tmdbID), item.mediaType), let runtime = detail.runtime else { continue }
            item.runtime = Int32(runtime)
        }
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch { print("Save failed: \(error)") }
    }

    // MARK: Model

    /// Built in code so there's no .xcdatamodeld to keep in sync. CloudKit needs every
    /// attribute optional or defaulted, and no unique constraints. Keep CloudKit/schema.ckdb in step with it.
    private static let model: NSManagedObjectModel = {
        func attr(_ name: String, _ type: NSAttributeType, _ defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            a.defaultValue = defaultValue
            return a
        }
        let tracked = NSEntityDescription()
        tracked.name = "Tracked"
        tracked.managedObjectClassName = NSStringFromClass(Tracked.self)
        tracked.properties = [
            attr("tmdbID", .integer64AttributeType, 0), attr("mediaTypeRaw", .stringAttributeType),
            attr("statusRaw", .stringAttributeType), attr("name", .stringAttributeType),
            attr("posterPath", .stringAttributeType), attr("backdropPath", .stringAttributeType),
            attr("releaseDate", .stringAttributeType), attr("rating", .integer16AttributeType, 0),
            attr("runtime", .integer32AttributeType, 0), attr("addedAt", .dateAttributeType),
            attr("watchedAt", .dateAttributeType), attr("position", .integer32AttributeType, 0), attr("note", .stringAttributeType),
        ]
        let episode = NSEntityDescription()
        episode.name = "WatchedEpisode"
        episode.managedObjectClassName = NSStringFromClass(WatchedEpisode.self)
        episode.properties = [
            attr("showID", .integer64AttributeType, 0), attr("season", .integer16AttributeType, 0),
            attr("episode", .integer16AttributeType, 0), attr("runtime", .integer32AttributeType, 0),
            attr("watchedAt", .dateAttributeType),
        ]
        let marathon = NSEntityDescription()
        marathon.name = "Marathon"
        marathon.managedObjectClassName = NSStringFromClass(Marathon.self)
        marathon.properties = [
            attr("uuid", .stringAttributeType), attr("name", .stringAttributeType),
            attr("piecesData", .binaryDataAttributeType), attr("daysData", .binaryDataAttributeType),
            attr("breakMinutes", .integer16AttributeType, 15), attr("runOver", .booleanAttributeType, true),
            attr("createdAt", .dateAttributeType),
        ]
        let model = NSManagedObjectModel()
        model.entities = [tracked, episode, marathon]
        return model
    }()
}

/// Small user preferences that don't belong in the synced library.
enum Prefs {
    private static let defaults = UserDefaults.standard

    static var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        set { defaults.set(newValue, forKey: "onboarded") }
    }
    static var region: String {
        get { defaults.string(forKey: "region") ?? Locale.current.region?.identifier ?? "US" }
        set { defaults.set(newValue, forKey: "region") }
    }
    static var services: Set<Int> {
        get { Set(defaults.array(forKey: "services") as? [Int] ?? []) }
        set { defaults.set(Array(newValue), forKey: "services") }
    }
}
