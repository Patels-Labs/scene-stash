import CoreData
import UIKit

enum TrackStatus: String, CaseIterable {
    case watchlist, watching, seen

    var label: String {
        switch self {
        case .watchlist: "Watchlist"
        case .watching: "Watching"
        case .seen: "Watched"
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
    /// Every time you've seen it, as JSON. Nil until there's more than the first time to remember.
    @NSManaged var viewingsData: Data?

    var mediaType: MediaType { MediaType(rawValue: mediaTypeRaw ?? "") ?? .movie }
    var status: TrackStatus {
        get { TrackStatus(rawValue: statusRaw ?? "") ?? .watchlist }
        set { statusRaw = newValue.rawValue }
    }
    var title: Title {
        Title(id: Int(tmdbID), mediaType: mediaType, name: name ?? "", posterPath: posterPath, backdropPath: backdropPath, date: releaseDate)
    }

    /// Oldest first. Before any rewatch it's just the first time, from `watchedAt`.
    var viewings: [Viewing] {
        get {
            if let data = viewingsData, let list = try? JSONDecoder().decode([Viewing].self, from: data) { return list }
            return status == .seen ? watchedAt.map { [Viewing(date: $0)] } ?? [] : []
        }
        set { viewingsData = try? JSONEncoder().encode(newValue.sorted { $0.date < $1.date }) }
    }
}

nonisolated struct Viewing: Codable, Hashable {
    var date: Date
    var place: String? = nil
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

    static let containerID = "iCloud.com.heetpatel.scenestash"

    /// Your library, mirrored to your private iCloud database.
    private(set) var privateStore: NSPersistentStore?
    /// Movie nights other people shared with you, mirrored from the shared iCloud database.
    private(set) var sharedStore: NSPersistentStore?

    private init() {
        container = NSPersistentCloudKitContainer(name: "SceneStash", managedObjectModel: Self.model)
        let description = container.persistentStoreDescriptions.first!
        description.cloudKitContainerOptions = Self.cloudEnabled ? NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerID) : nil
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let privateURL = description.url!
        let sharedURL = privateURL.deletingLastPathComponent().appendingPathComponent("SceneStash-shared.sqlite")
        if Self.cloudEnabled {
            let shared = description.copy() as! NSPersistentStoreDescription
            shared.url = sharedURL
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerID)
            options.databaseScope = .shared
            shared.cloudKitContainerOptions = options
            container.persistentStoreDescriptions.append(shared)
        }
        container.loadPersistentStores { _, error in
            // Sync failures (no iCloud account, schema not deployed) don't fail the load; local data keeps working.
            if let error { print("Store failed to load: \(error)") }
        }
        privateStore = container.persistentStoreCoordinator.persistentStore(for: privateURL)
        sharedStore = container.persistentStoreCoordinator.persistentStore(for: sharedURL)
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let ended = event.endDate else { return }
            let error = event.error?.localizedDescription
            MainActor.assumeIsolated {
                Store.shared.lastSync = (ended, error)
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
        // Not out yet: it can only be wanted, not watched.
        let status = title.unreleased ? .watchlist : status
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
        if status == .seen && item.status != .seen {
            // Finishing a rewatch: the earlier times are kept, so this is one more.
            if item.viewingsData != nil { item.viewings.append(Viewing(date: .now)) }
            item.watchedAt = .now
            item.position = 0
        }
        // Back on the Watchlist means not started: no place in it to keep.
        if status == .watchlist { item.position = 0 }
        item.status = status
        save()
        endSession(title, status: status)
        return item
    }

    /// A film that's no longer Watching keeps no clock: its Live Activity ends, as finished if it was seen.
    private func endSession(_ title: Title, status: TrackStatus?) {
        guard status != .watching, let s = WatchSession.shared.state, s.id == title.id, s.key == nil, title.mediaType == .movie else { return }
        Task { status == .seen ? await WatchSession.shared.finish() : await WatchSession.shared.stop(saving: false) }
    }

    func setRating(_ rating: Int, for title: Title) {
        let item = tracked(title.id, title.mediaType) ?? track(title, status: .seen)
        item.rating = Int16(rating)
        mirrorToNights(title)
        mirrorToFriends(title)
        save()
    }

    /// Records where you stopped in a film; anything past the start puts it on the Watching shelf.
    func setPosition(_ seconds: Int, for title: Title, runtime: Int?) {
        let item = tracked(title.id, title.mediaType) ?? track(title, status: .watching, runtime: runtime)
        if let runtime, item.runtime == 0 { item.runtime = Int32(runtime) }
        item.position = Int32(max(seconds, 0))
        if seconds <= 0, item.status == .watching, title.mediaType == .movie {
            // Dragged back to the start: it's not being watched any more.
            item.status = item.watchedAt != nil ? .seen : .watchlist
        } else if seconds > 0, item.status != .watching {
            // Starting it again: write down the times so far before Watching hides them.
            if item.status == .seen { item.viewings = item.viewings }
            item.status = .watching
        }
        save()
    }

    func setNote(_ note: String?, for title: Title) {
        guard let item = tracked(title.id, title.mediaType) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = trimmed?.isEmpty == false ? trimmed : nil
        mirrorToNights(title)
        mirrorToFriends(title)
        save()
    }

    /// Another time you saw it. The first add also writes down the time it was marked seen.
    func addViewing(_ title: Title, date: Date, place: String?, runtime: Int? = nil) {
        let item = tracked(title.id, title.mediaType) ?? track(title, status: .watchlist, runtime: runtime)
        var list = item.viewings
        if item.status != .seen { item.status = .seen; item.position = 0 }
        list.append(Viewing(date: date, place: place?.isEmpty == true ? nil : place))
        item.viewings = list
        item.watchedAt = max(item.watchedAt ?? date, date)
        save()
    }

    func removeViewing(_ viewing: Viewing, of title: Title) {
        guard let item = tracked(title.id, title.mediaType) else { return }
        var list = item.viewings
        guard list.count > 1, let i = list.firstIndex(of: viewing) else { return }
        list.remove(at: i)
        item.viewings = list
        item.watchedAt = list.last?.date
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
        endSession(title, status: nil)
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
        // A show's position is how far into its next episode you are, and that episode has just changed.
        tracked(show.id, .tv)?.position = 0
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
            attr("viewingsData", .binaryDataAttributeType),
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
        let night = NSEntityDescription()
        night.name = "MovieNight"
        night.managedObjectClassName = NSStringFromClass(MovieNight.self)
        let note = NSEntityDescription()
        note.name = "NightNote"
        note.managedObjectClassName = NSStringFromClass(NightNote.self)
        let notes = NSRelationshipDescription()
        notes.name = "notes"
        notes.destinationEntity = note
        notes.minCount = 0
        notes.maxCount = 0
        notes.deleteRule = .cascadeDeleteRule
        notes.isOptional = true
        let noteNight = NSRelationshipDescription()
        noteNight.name = "night"
        noteNight.destinationEntity = night
        noteNight.maxCount = 1
        noteNight.deleteRule = .nullifyDeleteRule
        noteNight.isOptional = true
        notes.inverseRelationship = noteNight
        noteNight.inverseRelationship = notes
        night.properties = [
            attr("uuid", .stringAttributeType), attr("tmdbID", .integer64AttributeType, 0),
            attr("name", .stringAttributeType), attr("posterPath", .stringAttributeType),
            attr("backdropPath", .stringAttributeType), attr("runtime", .integer32AttributeType, 0),
            attr("showtime", .dateAttributeType), attr("cinema", .stringAttributeType),
            attr("address", .stringAttributeType), attr("screen", .stringAttributeType),
            attr("seats", .stringAttributeType), attr("booked", .booleanAttributeType, false),
            attr("bookedBy", .stringAttributeType), attr("createdAt", .dateAttributeType), notes,
        ]
        note.properties = [
            attr("uuid", .stringAttributeType), attr("authorID", .stringAttributeType),
            attr("authorName", .stringAttributeType), attr("text", .stringAttributeType),
            attr("rating", .integer16AttributeType, 0), attr("createdAt", .dateAttributeType), noteNight,
        ]
        /// A to-many and its inverse, cascading from the parent.
        func children(_ name: String, of parent: NSEntityDescription, _ child: NSEntityDescription, back: String) -> (NSRelationshipDescription, NSRelationshipDescription) {
            let many = NSRelationshipDescription()
            many.name = name
            many.destinationEntity = child
            many.minCount = 0
            many.maxCount = 0
            many.deleteRule = .cascadeDeleteRule
            many.isOptional = true
            let one = NSRelationshipDescription()
            one.name = back
            one.destinationEntity = parent
            one.maxCount = 1
            one.deleteRule = .nullifyDeleteRule
            one.isOptional = true
            many.inverseRelationship = one
            one.inverseRelationship = many
            return (many, one)
        }
        let photo = NSEntityDescription()
        photo.name = "NightPhoto"
        photo.managedObjectClassName = NSStringFromClass(NightPhoto.self)
        let (photos, photoNight) = children("photos", of: night, photo, back: "night")
        night.properties.append(photos)
        let image = attr("imageData", .binaryDataAttributeType)
        image.allowsExternalBinaryDataStorage = true
        photo.properties = [
            attr("uuid", .stringAttributeType), attr("authorID", .stringAttributeType), attr("authorName", .stringAttributeType),
            image, attr("createdAt", .dateAttributeType), photoNight,
        ]
        let friend = NSEntityDescription()
        friend.name = "Friend"
        friend.managedObjectClassName = NSStringFromClass(Friend.self)
        let rec = NSEntityDescription()
        rec.name = "Recommendation"
        rec.managedObjectClassName = NSStringFromClass(Recommendation.self)
        let (recs, recFriend) = children("recs", of: friend, rec, back: "friend")
        friend.properties = [attr("uuid", .stringAttributeType), attr("createdAt", .dateAttributeType), recs]
        rec.properties = [
            attr("uuid", .stringAttributeType), attr("authorID", .stringAttributeType), attr("authorName", .stringAttributeType),
            attr("tmdbID", .integer64AttributeType, 0), attr("mediaTypeRaw", .stringAttributeType), attr("name", .stringAttributeType),
            attr("posterPath", .stringAttributeType), attr("backdropPath", .stringAttributeType), attr("note", .stringAttributeType),
            attr("senderRating", .integer16AttributeType, 0), attr("rating", .integer16AttributeType, 0), attr("line", .stringAttributeType),
            attr("ratedAt", .dateAttributeType), attr("createdAt", .dateAttributeType), recFriend,
        ]
        let model = NSManagedObjectModel()
        model.entities = [tracked, episode, marathon, night, note, photo, friend, rec]
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
