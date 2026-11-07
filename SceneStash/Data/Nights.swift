import CloudKit
import CoreData

/// A night out at the pictures. Shared with friends as its own iCloud share, so everyone sees one ticket.
@objc(MovieNight)
final class MovieNight: NSManagedObject {
    @NSManaged var uuid: String?
    @NSManaged var tmdbID: Int64
    @NSManaged var name: String?
    @NSManaged var posterPath: String?
    @NSManaged var backdropPath: String?
    @NSManaged var runtime: Int32
    /// When doors open: the time on the ticket.
    @NSManaged var showtime: Date?
    @NSManaged var cinema: String?
    @NSManaged var address: String?
    @NSManaged var screen: String?
    @NSManaged var seats: String?
    @NSManaged var booked: Bool
    /// Name of whoever marked it booked, as their friends see it.
    @NSManaged var bookedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var notes: Set<NightNote>?

    var title: Title {
        Title(id: Int(tmdbID), mediaType: .movie, name: name ?? "", posterPath: posterPath, backdropPath: backdropPath, date: nil)
    }
    func status(at now: Date = .now) -> NightStatus {
        NightStatus.at(now, showtime: showtime ?? .distantFuture, runtime: Int(runtime), booked: booked)
    }
    var lightsUp: Date? { showtime.map { NightStatus.lightsUp($0, runtime: Int(runtime)) } }
    /// "Odeon Luxe · Screen 1 · H7–H10", or nil before a cinema is picked.
    var whereLine: String? {
        let bits = [cinema, screen.map { "Screen \($0)" }, seats].compactMap { $0 }.filter { !$0.isEmpty }
        return cinema?.isEmpty == false ? bits.joined(separator: " · ") : nil
    }
    /// Someone else's night you were invited to.
    @MainActor var isGuest: Bool {
        guard let store = objectID.persistentStore else { return false }
        return store == Store.shared.sharedStore
    }
}

/// One person's line and rating in the scrapbook, written once the credits roll.
@objc(NightNote)
final class NightNote: NSManagedObject {
    @NSManaged var uuid: String?
    @NSManaged var authorID: String?
    @NSManaged var authorName: String?
    @NSManaged var text: String?
    @NSManaged var rating: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var night: MovieNight?
}

/// Someone on a night's share.
struct Guest: Hashable {
    let name: String
    let isMe: Bool
    let planned: Bool
    let accepted: Bool
    var initial: String { String(name.prefix(1)).uppercased() }
}

extension Store {
    func nights() -> [MovieNight] {
        let request = NSFetchRequest<MovieNight>(entityName: "MovieNight")
        request.sortDescriptors = [NSSortDescriptor(key: "showtime", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func nights(for title: Title) -> [MovieNight] {
        nights().filter { Int($0.tmdbID) == title.id }
    }

    /// A new, unsaved night for a film; the plan form fills it in and saves.
    func newNight(for title: Title, runtime: Int?) -> MovieNight {
        let night = MovieNight(context: context)
        if let privateStore { context.assign(night, to: privateStore) }
        night.uuid = UUID().uuidString
        night.createdAt = .now
        night.tmdbID = Int64(title.id)
        night.name = title.name
        night.posterPath = title.posterPath
        night.backdropPath = title.backdropPath
        night.runtime = Int32(runtime ?? 0)
        return night
    }

    func delete(_ night: MovieNight) {
        context.delete(night)
        save()
    }

    func myNote(on night: MovieNight) -> NightNote? {
        night.notes?.first { $0.authorID == Prefs.me }
    }

    /// Writes your one line and rating for the night. Notes live in the night's store so they travel with its share.
    func setNote(_ text: String?, rating: Int, on night: MovieNight, as name: String?) {
        let note = myNote(on: night) ?? {
            let n = NightNote(context: context)
            if let store = night.objectID.persistentStore ?? privateStore { context.assign(n, to: store) }
            n.uuid = UUID().uuidString
            n.authorID = Prefs.me
            n.createdAt = .now
            n.night = night
            return n
        }()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        note.text = trimmed?.isEmpty == false ? trimmed : nil
        note.rating = Int16(rating)
        note.authorName = name
        save()
    }

    /// Keeps your stash in step with your nights out: the film goes on Watching when the lights go down
    /// and Seen, timed to when they came up, once the credits roll. Each step happens once per night,
    /// so changing it by hand afterwards sticks.
    func updateFromNights(now: Date = .now) {
        var watching = Prefs.watchingNights, done = Prefs.stashedNights
        for night in nights() {
            guard let uuid = night.uuid else { continue }
            let current = tracked(night.title.id, .movie)?.status
            let runtime = night.runtime > 0 ? Int(night.runtime) : nil
            switch night.status(at: now) {
            case .lightsDown where !watching.contains(uuid):
                watching.insert(uuid)
                if current != .seen && current != .watching { track(night.title, status: .watching, runtime: runtime) }
            case .creditsRolled where !done.contains(uuid):
                done.insert(uuid)
                if current != .seen { track(night.title, status: .seen, runtime: runtime).watchedAt = night.lightsUp }
            default: break
            }
        }
        guard watching != Prefs.watchingNights || done != Prefs.stashedNights else { return }
        Prefs.watchingNights = watching
        Prefs.stashedNights = done
        save()
    }

    /// Today's night out, if it hasn't finished yet.
    func tonightsNight(now: Date = .now) -> MovieNight? {
        nights().first { night in
            guard let showtime = night.showtime else { return false }
            return Calendar.current.isDate(showtime, inSameDayAs: now) && night.status(at: now) != .creditsRolled
        }
    }

    func night(uuid: String) -> MovieNight? {
        nights().first { $0.uuid == uuid }
    }

    // MARK: Sharing

    var cloudContainer: CKContainer { CKContainer(identifier: Self.containerID) }

    func share(for night: MovieNight) -> CKShare? {
        guard Self.cloudEnabled, !night.objectID.isTemporaryID else { return nil }
        return (try? container.fetchShares(matching: [night.objectID]))?[night.objectID]
    }

    /// Moves the night into its own share zone and returns the share for the invite sheet.
    func makeShare(for id: NSManagedObjectID) async throws -> CKShare {
        guard let night = try context.existingObject(with: id) as? MovieNight else { throw CKError(.unknownItem) }
        let (_, share, _) = try await container.share([night], to: nil)
        share[CKShare.SystemFieldKey.title] = "Movie night: \(night.name ?? "a film")"
        share.publicPermission = .none
        return share
    }

    /// Called when you tap someone's invite link.
    func accept(_ metadata: CKShare.Metadata) {
        guard let sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error { print("Couldn't accept share: \(error)") }
        }
    }

    /// Everyone on the night's share, the planner first. Just you when it isn't shared yet.
    func guests(for night: MovieNight) -> [Guest] {
        guard let share = share(for: night) else { return [Guest(name: "You", isMe: true, planned: true, accepted: true)] }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return share.participants
            .filter { $0.acceptanceStatus != .removed }
            .map { p in
                let isMe = p == share.currentUserParticipant
                let name = isMe ? "You" : p.userIdentity.nameComponents.map(formatter.string(from:)).flatMap { $0.isEmpty ? nil : $0 } ?? "Invited"
                return Guest(name: name, isMe: isMe, planned: p.role == .owner, accepted: p.acceptanceStatus == .accepted)
            }
            .sorted { $0.planned && !$1.planned }
    }

    /// Your name as friends on this night see it, for notes and "booked by".
    func myName(on night: MovieNight) -> String? {
        guard let me = share(for: night)?.currentUserParticipant?.userIdentity.nameComponents else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return formatter.string(from: me).isEmpty ? nil : formatter.string(from: me)
    }

    /// Learns your iCloud user record name once, so your note can be told apart from your friends'.
    func loadIdentity() async {
        guard Self.cloudEnabled, Prefs.me == Prefs.localMe else { return }
        if let id = try? await cloudContainer.userRecordID() { Prefs.me = id.recordName }
    }
}

extension Prefs {
    /// Your iCloud user record name, or a stand-in until it's known (and in local previews).
    static let localMe = "local-user"
    static var me: String {
        get { UserDefaults.standard.string(forKey: "me") ?? localMe }
        set { UserDefaults.standard.set(newValue, forKey: "me") }
    }
    static var watchingNights: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "watchingNights") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "watchingNights") }
    }
    static var stashedNights: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "stashedNights") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "stashedNights") }
    }
}
