import Foundation

/// "I've got…": what fits in the time you have. Each candidate is a run of pieces watched in order
/// (the rest of a film, or a show's next episodes); as many as fit are taken, stopping at the first that doesn't.
nonisolated enum TimeFit {
    struct Fit: Equatable {
        let index: Int
        let count: Int
        let used: Int
        let spare: Int
    }

    /// Candidates that fit at least one piece, tightest fit first. Ties keep the caller's order.
    static func fits(_ candidates: [[Int]], minutes: Int) -> [Fit] {
        candidates.enumerated().compactMap { i, pieces -> Fit? in
            var used = 0, count = 0
            for p in pieces {
                guard used + p <= minutes else { break }
                used += p
                count += 1
            }
            return count == 0 ? nil : Fit(index: i, count: count, used: used, spare: minutes - used)
        }
        .sorted { $0.spare == $1.spare ? $0.index < $1.index : $0.spare < $1.spare }
    }
}
