import Foundation

/// Holiday ticket icons are offered in the picker from two weeks before each holiday to a week after.
/// They're never switched on for you; outside the window they simply aren't listed.
nonisolated enum Holiday: String, CaseIterable, Sendable {
    case diwali, christmas, newYear, lunarNewYear, eid, holi, easter, july4

    var title: String {
        switch self {
        case .diwali: "Diwali"
        case .christmas: "Christmas"
        case .newYear: "New Year"
        case .lunarNewYear: "Lunar New Year"
        case .eid: "Eid"
        case .holi: "Holi"
        case .easter: "Easter"
        case .july4: "Fourth of July"
        }
    }

    /// The alternate icon's asset name.
    var iconName: String {
        switch self {
        case .diwali: "AppIcon-Diwali"
        case .christmas: "AppIcon-Christmas"
        case .newYear: "AppIcon-NewYear"
        case .lunarNewYear: "AppIcon-LunarNewYear"
        case .eid: "AppIcon-Eid"
        case .holi: "AppIcon-Holi"
        case .easter: "AppIcon-Easter"
        case .july4: "AppIcon-July4"
        }
    }

    static let before: TimeInterval = 14 * 86400
    static let after: TimeInterval = 7 * 86400

    /// The holiday's dates in a Gregorian year (Eid has two: al-Fitr and al-Adha).
    func dates(in year: Int) -> [Date] {
        let g = Calendar(identifier: .gregorian)
        func day(_ m: Int, _ d: Int, _ y: Int = year) -> Date? { g.date(from: DateComponents(year: y, month: m, day: d)) }
        switch self {
        case .christmas: return [day(12, 25)].compactMap { $0 }
        case .newYear: return [day(1, 1)].compactMap { $0 }
        case .july4: return [day(7, 4)].compactMap { $0 }
        case .easter: return [Self.easter(year)].compactMap { $0 }
        case .lunarNewYear:
            // The first day of the first month in the Chinese calendar that falls in this Gregorian year.
            let chinese = Calendar(identifier: .chinese)
            guard let mid = day(6, 1) else { return [] }
            let era = chinese.dateComponents([.era, .year], from: mid)
            return [chinese.date(from: DateComponents(era: era.era, year: era.year, month: 1, day: 1))].compactMap { $0 }
        case .eid:
            // 1 Shawwal (al-Fitr) and 10 Dhu al-Hijjah (al-Adha), for each Hijri year overlapping this one.
            // ponytail: calculated (Umm al-Qura) dates; local moon sighting can shift them by a day, well inside the window.
            let hijri = Calendar(identifier: .islamicUmmAlQura)
            let years = Set([day(1, 1), day(12, 31)].compactMap { $0 }.map { hijri.component(.year, from: $0) })
            return years.flatMap { y in
                [DateComponents(year: y, month: 10, day: 1), DateComponents(year: y, month: 12, day: 10)].compactMap(hijri.date(from:))
            }.filter { g.component(.year, from: $0) == year }
        case .diwali, .holi:
            // Hindu lunisolar dates aren't in Foundation, so they come from a table.
            // ponytail: covers 2026–2035; extend the table before then.
            let table: [Int: (Int, Int)] = self == .diwali
                ? [2026: (11, 8), 2027: (10, 29), 2028: (10, 17), 2029: (11, 5), 2030: (10, 26), 2031: (11, 14), 2032: (11, 2), 2033: (10, 22), 2034: (11, 10), 2035: (10, 30)]
                : [2026: (3, 4), 2027: (3, 22), 2028: (3, 11), 2029: (3, 1), 2030: (3, 20), 2031: (3, 9), 2032: (3, 27), 2033: (3, 16), 2034: (3, 5), 2035: (3, 24)]
            return table[year].flatMap { day($0.0, $0.1) }.map { [$0] } ?? []
        }
    }

    /// Western Easter Sunday (anonymous Gregorian algorithm).
    static func easter(_ y: Int) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: month, day: day))
    }

    /// The occurrence whose window contains `now`, if any.
    func window(containing now: Date) -> (holiday: Date, ends: Date)? {
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        for date in (year - 1...year + 1).flatMap(dates(in:)) {
            let ends = date.addingTimeInterval(Self.after)
            if now >= date.addingTimeInterval(-Self.before), now < ends { return (date, ends) }
        }
        return nil
    }

    /// Holidays whose icons are on offer right now, soonest-ending first.
    static func available(at now: Date = .now) -> [(Holiday, ends: Date)] {
        allCases.compactMap { h in h.window(containing: now).map { (h, $0.ends) } }.sorted { $0.ends < $1.ends }
    }
}
