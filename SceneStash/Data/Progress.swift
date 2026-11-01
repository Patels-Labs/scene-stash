import Foundation

/// A season/episode position, ordered by season then episode.
nonisolated struct EpisodeKey: Hashable, Comparable {
    let season: Int
    let episode: Int
    static func < (a: EpisodeKey, b: EpisodeKey) -> Bool { (a.season, a.episode) < (b.season, b.episode) }
    var label: String { "S\(season) · E\(episode)" }
}

nonisolated enum Progress {
    /// The episode after the furthest one watched, or nil when caught up.
    /// `seasons` maps season number → episode count (specials excluded); `aired` caps it at the latest aired episode.
    static func nextUp(seasons: [Int: Int], watched: Set<EpisodeKey>, aired: EpisodeKey?) -> EpisodeKey? {
        let order = seasons.keys.sorted()
        guard let first = order.first else { return nil }
        var next = EpisodeKey(season: first, episode: 1)
        if let last = watched.max() {
            if last.episode < seasons[last.season, default: 0] {
                next = EpisodeKey(season: last.season, episode: last.episode + 1)
            } else if let s = order.first(where: { $0 > last.season }) {
                next = EpisodeKey(season: s, episode: 1)
            } else {
                return nil
            }
        }
        if let aired, aired < next { return nil }
        return next
    }

    /// Episodes aired but not watched.
    static func remaining(seasons: [Int: Int], watched: Set<EpisodeKey>, aired: EpisodeKey?) -> Int {
        var count = 0
        for (s, n) in seasons where n > 0 {
            for e in 1...n {
                let key = EpisodeKey(season: s, episode: e)
                if let aired, aired < key { continue }
                if !watched.contains(key) { count += 1 }
            }
        }
        return count
    }

    /// Consecutive days ending today (or yesterday) with at least one watch.
    static func streak(days: [Date], calendar: Calendar = .current, now: Date = .now) -> Int {
        let set = Set(days.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        if !set.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while set.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
