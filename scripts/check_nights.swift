// Run: scripts/check.sh — asserts how a night out moves through its stages in NightStatus.swift.
let show = Date(timeIntervalSince1970: 1_800_000_000)
let min: (Int) -> Date = { show + TimeInterval($0 * 60) }

assert(NightStatus.at(min(-60), showtime: show, runtime: 100, booked: false) == .noTickets)
assert(NightStatus.at(min(-60), showtime: show, runtime: 100, booked: true) == .ticketsInHand)
assert(NightStatus.at(min(0), showtime: show, runtime: 100, booked: true) == .lightsDown, "doors at the booked time")
assert(NightStatus.at(min(119), showtime: show, runtime: 100, booked: true) == .lightsDown, "20 min of trailers first")
assert(NightStatus.at(min(120), showtime: show, runtime: 100, booked: true) == .creditsRolled)
assert(NightStatus.at(min(10), showtime: show, runtime: 100, booked: false) == .lightsDown, "went without marking it booked")
assert(NightStatus.at(min(130), showtime: show, runtime: 0, booked: true) == .lightsDown, "unknown runtime counts as two hours")
print("night checks passed")
