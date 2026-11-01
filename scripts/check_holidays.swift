// Holiday icon windows: two weeks before to a week after.
do {
    let g = Calendar(identifier: .gregorian)
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { g.date(from: DateComponents(year: y, month: m, day: day, hour: 12))! }
    func on(_ date: Date) -> Set<Holiday> { Set(Holiday.available(at: date).map(\.0)) }

    assert(g.dateComponents([.month, .day], from: Holiday.easter(2027)!) == DateComponents(month: 3, day: 28), "Easter 2027")
    assert(g.dateComponents([.month, .day], from: Holiday.easter(2026)!) == DateComponents(month: 4, day: 5), "Easter 2026")
    assert(on(d(2026, 11, 1)) == [.diwali], "Diwali (8 Nov) is on offer on 1 Nov")
    assert(on(d(2026, 10, 20)).isEmpty, "too early for Diwali")
    assert(on(d(2026, 11, 16)).isEmpty, "Diwali window closed")
    assert(on(d(2026, 12, 20)) == [.christmas, .newYear], "Christmas and New Year overlap")
    assert(on(d(2027, 1, 7)) == [.newYear], "New Year lingers a week")
    assert(on(d(2027, 2, 1)).contains(.lunarNewYear), "Lunar New Year 2027 is 6 Feb")
    assert(on(d(2027, 3, 5)).contains(.eid), "Eid al-Fitr 2027 is around 10 Mar")
    assert(on(d(2027, 3, 20)).isSuperset(of: [.holi, .easter]), "Holi and Easter overlap in 2027")
    assert(on(d(2027, 6, 25)) == [.july4])
    assert(on(d(2027, 8, 15)).isEmpty, "nothing in mid-August")
    print("holiday checks passed")
}
