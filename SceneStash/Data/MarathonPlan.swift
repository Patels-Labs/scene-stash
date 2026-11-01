import Foundation

/// One thing to watch in a marathon: a film, or an episode of a show.
nonisolated struct Piece: Codable, Hashable, Sendable {
    let id: Int                 // TMDB id of the film or show
    let isEpisode: Bool
    let name: String            // the film, or the show
    let detail: String?         // episode name
    let poster: String?
    let backdrop: String?
    let minutes: Int
    var season: Int? = nil
    var episode: Int? = nil
}

/// A day of the marathon: when doors open and when the lights come up.
nonisolated struct MarathonDay: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
}

nonisolated struct PlannedSlot: Hashable, Sendable {
    let piece: Piece
    let start: Date
    let end: Date
    /// Starts before lights up but finishes after it.
    let overruns: Bool
}

nonisolated enum MarathonPlan {
    /// How late the last piece of a day may finish when running over is allowed.
    static let overrunLimit: TimeInterval = 3600

    /// Lays pieces in order across the days, a break between each. A piece that would end after lights up
    /// either runs over (if allowed, by up to an hour) or waits for the next day. Pieces that fit nowhere are `left`.
    static func plan(_ pieces: [Piece], days: [MarathonDay], breakMinutes: Int, runOver: Bool) -> (days: [[PlannedSlot]], left: [Piece]) {
        var queue = pieces[...]
        var out: [[PlannedSlot]] = []
        for day in days {
            var slots: [PlannedSlot] = []
            var t = day.start
            while let piece = queue.first {
                let end = t.addingTimeInterval(TimeInterval(piece.minutes * 60))
                if end <= day.end {
                    slots.append(PlannedSlot(piece: piece, start: t, end: end, overruns: false))
                } else if runOver, t < day.end, end <= day.end.addingTimeInterval(overrunLimit) {
                    slots.append(PlannedSlot(piece: piece, start: t, end: end, overruns: true))
                    queue.removeFirst()
                    break
                } else {
                    break
                }
                queue.removeFirst()
                t = end.addingTimeInterval(TimeInterval(breakMinutes * 60))
            }
            out.append(slots)
        }
        return (out, Array(queue))
    }
}
