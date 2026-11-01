// Run: scripts/check.sh — asserts the pure tracking logic in Progress.swift.
import Foundation

func k(_ s: Int, _ e: Int) -> EpisodeKey { EpisodeKey(season: s, episode: e) }
let seasons = [1: 3, 2: 2]

assert(Progress.nextUp(seasons: seasons, watched: [], aired: nil) == k(1, 1))
assert(Progress.nextUp(seasons: seasons, watched: [k(1, 1), k(1, 2)], aired: nil) == k(1, 3))
assert(Progress.nextUp(seasons: seasons, watched: [k(1, 3)], aired: nil) == k(2, 1), "rolls over to next season")
assert(Progress.nextUp(seasons: seasons, watched: [k(2, 2)], aired: nil) == nil, "caught up")
assert(Progress.nextUp(seasons: seasons, watched: [k(1, 3)], aired: k(1, 3)) == nil, "next not aired yet")
assert(Progress.remaining(seasons: seasons, watched: [k(1, 1)], aired: k(2, 1)) == 3)

let cal = Calendar(identifier: .gregorian)
let now = Date(timeIntervalSince1970: 1_800_000_000)
let day: (Int) -> Date = { cal.date(byAdding: .day, value: -$0, to: now)! }
assert(Progress.streak(days: [day(0), day(1), day(2), day(4)], calendar: cal, now: now) == 3)
assert(Progress.streak(days: [day(1), day(2)], calendar: cal, now: now) == 2, "yesterday keeps the streak")
assert(Progress.streak(days: [day(3)], calendar: cal, now: now) == 0)
print("progress checks passed")
