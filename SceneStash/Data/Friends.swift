import CloudKit
import CoreData

/// You and one friend: a shared iCloud zone, like a night's, that either of you can pass a title into.
@objc(Friend)
final class Friend: NSManagedObject {
    @NSManaged var uuid: String?
    @NSManaged var createdAt: Date?
    @NSManaged var recs: Set<Recommendation>?
}

/// A title passed on to a friend with a note, and later their rating and line back.
@objc(Recommendation)
final class Recommendation: NSManagedObject {
    @NSManaged var uuid: String?
    @NSManaged var authorID: String?
    @NSManaged var authorName: String?
    @NSManaged var tmdbID: Int64
    @NSManaged var mediaTypeRaw: String?
    @NSManaged var name: String?
    @NSManaged var posterPath: String?
    @NSManaged var backdropPath: String?
    @NSManaged var note: String?
    /// What the sender rated it, shown on the card.
    @NSManaged var senderRating: Int16
    /// What the friend rated it once they'd watched it; 0 until then.
    @NSManaged var rating: Int16
    @NSManaged var line: String?
    @NSManaged var ratedAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var friend: Friend?

    var title: Title {
        Title(id: Int(tmdbID), mediaType: MediaType(rawValue: mediaTypeRaw ?? "") ?? .movie, name: name ?? "", posterPath: posterPath, backdropPath: backdropPath)
    }
    @MainActor var isMine: Bool { authorID == Prefs.me }
}

extension Store {
    func friends() -> [Friend] {
        let request = NSFetchRequest<Friend>(entityName: "Friend")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func recommendations() -> [Recommendation] {
        let request = NSFetchRequest<Recommendation>(entityName: "Recommendation")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    /// Passed to you and not watched yet, newest first.
    func fromFriends() -> [Recommendation] {
        recommendations().filter { !$0.isMine && tracked(Int($0.tmdbID), $0.title.mediaType)?.status != .seen }
    }

    /// A new friend slot of your own, ready to share with whoever you invite.
    func newFriend() -> Friend {
        let f = Friend(context: context)
        if let privateStore { context.assign(f, to: privateStore) }
        f.uuid = UUID().uuidString
        f.createdAt = .now
        save()
        return f
    }

    /// The other person on the share; nil until they've accepted.
    func friendName(_ friend: Friend) -> String? {
        guard let share = share(for: friend) else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return share.participants
            .filter { $0 != share.currentUserParticipant && $0.acceptanceStatus == .accepted }
            .compactMap { $0.userIdentity.nameComponents.map(formatter.string(from:)) }
            .first { !$0.isEmpty }
    }

    func recommend(_ title: Title, to friend: Friend, note: String?) {
        let rec = Recommendation(context: context)
        if let store = friend.objectID.persistentStore ?? privateStore { context.assign(rec, to: store) }
        rec.uuid = UUID().uuidString
        rec.authorID = Prefs.me
        rec.authorName = myName(on: friend)
        rec.tmdbID = Int64(title.id)
        rec.mediaTypeRaw = title.mediaType.rawValue
        rec.name = title.name
        rec.posterPath = title.posterPath
        rec.backdropPath = title.backdropPath
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        rec.note = trimmed?.isEmpty == false ? trimmed : nil
        rec.senderRating = tracked(title.id, title.mediaType)?.rating ?? 0
        rec.createdAt = .now
        rec.friend = friend
        save()
    }

    /// After you rate something a friend passed you, sends your rating and line back to them.
    func mirrorToFriends(_ title: Title) {
        guard let item = tracked(title.id, title.mediaType), item.rating > 0 else { return }
        for rec in recommendations() where !rec.isMine && rec.tmdbID == Int64(title.id) && rec.mediaTypeRaw == title.mediaType.rawValue {
            if rec.rating == 0 { rec.ratedAt = .now }
            rec.rating = item.rating
            rec.line = item.note
        }
    }

    /// Of what you've passed on and been rated, how many got 7 or more.
    func hitRate() -> (hits: Int, rated: Int) {
        let rated = recommendations().filter { $0.isMine && $0.rating > 0 }
        return (rated.filter { $0.rating >= 7 }.count, rated.count)
    }
}
