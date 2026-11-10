import Foundation

/// What a watched film adds to the passport: where and when it's from, who made it, what kind it is.
nonisolated struct FilmFact: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let year: Int?
    let countries: [String]
    let director: String?
    let genres: [String]
}

/// Cinema Passport: stamps earned from films you've watched. One film from a country earns it; a decade
/// takes 5, a director 3, a genre 10; milestones come at 10, 25, 50, 100 films and on.
nonisolated enum Passport {
    struct Stamp: Hashable {
        enum Kind: String { case country, decade, director, genre, milestone }
        let kind: Kind
        let name: String
        /// Film ids that count toward it, in the order you watched them.
        let films: [Int]
        let need: Int
        /// When the film that earned it was watched; nil while it's locked.
        let earnedOn: Date?

        var earned: Bool { earnedOn != nil }
        var progress: Double { Swift.min(Double(films.count) / Double(need), 1) }
    }

    static let needs: [Stamp.Kind: Int] = [.country: 1, .decade: 5, .director: 3, .genre: 10]
    static let milestones = [10, 25, 50, 100, 250, 500, 1000]

    static func decade(_ year: Int) -> String {
        let d = year / 10 * 10
        return d < 2000 ? "The '\(String(format: "%02d", d % 100))s" : "The \(d)s"
    }

    /// Every stamp you've earned or started on, plus the next milestone.
    static func stamps(_ watched: [(fact: FilmFact, date: Date)]) -> [Stamp] {
        let films = watched.sorted { $0.date < $1.date }
        var groups: [Stamp.Kind: [String: [(Int, Date)]]] = [:]
        for (f, date) in films {
            var keys: [(Stamp.Kind, String)] = f.countries.map { (.country, $0) } + f.genres.map { (.genre, $0) }
            if let y = f.year { keys.append((.decade, decade(y))) }
            if let d = f.director { keys.append((.director, d)) }
            for (kind, key) in keys { groups[kind, default: [:]][key, default: []].append((f.id, date)) }
        }
        var stamps: [Stamp] = []
        for (kind, byName) in groups {
            let need = needs[kind] ?? 1
            for (name, list) in byName {
                stamps.append(Stamp(kind: kind, name: name, films: list.map(\.0), need: need, earnedOn: list.count >= need ? list[need - 1].1 : nil))
            }
        }
        for m in milestones {
            let reached = films.count >= m
            stamps.append(Stamp(kind: .milestone, name: "\(m) Films", films: films.prefix(m).map(\.fact.id), need: m, earnedOn: reached ? films[m - 1].date : nil))
            if !reached { break }
        }
        return stamps
    }
}
