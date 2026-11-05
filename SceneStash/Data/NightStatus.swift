import Foundation

/// Where a night out is. Only "booked" is stored; the rest follows from the clock.
nonisolated enum NightStatus: Int, CaseIterable, Sendable {
    case noTickets, ticketsInHand, lightsDown, creditsRolled

    /// Ads and trailers between the booked time and the film.
    static let trailers: TimeInterval = 20 * 60

    static func filmStarts(_ showtime: Date) -> Date { showtime + trailers }

    /// Unknown runtimes count as two hours so the night doesn't end early.
    static func lightsUp(_ showtime: Date, runtime: Int) -> Date {
        filmStarts(showtime) + TimeInterval((runtime > 0 ? runtime : 120) * 60)
    }

    static func at(_ now: Date, showtime: Date, runtime: Int, booked: Bool) -> NightStatus {
        if now >= lightsUp(showtime, runtime: runtime) { return .creditsRolled }
        if now >= showtime { return .lightsDown }
        return booked ? .ticketsInHand : .noTickets
    }

    var label: String {
        switch self {
        case .noTickets: "No tickets yet"
        case .ticketsInHand: "Tickets in hand"
        case .lightsDown: "Lights down"
        case .creditsRolled: "Credits rolled"
        }
    }
}
