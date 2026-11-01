// Marathon scheduling: breaks, lights up, running over.
do {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ h: Double) -> Date { base.addingTimeInterval(h * 3600) }
    func film(_ n: String, _ m: Int) -> Piece { Piece(id: n.hashValue, isEpisode: false, name: n, detail: nil, poster: nil, backdrop: nil, minutes: m) }
    let hp = [film("1", 152), film("2", 161), film("3", 142), film("4", 157), film("5", 138), film("6", 153), film("7", 146), film("8", 130)]
    let sat = MarathonDay(start: at(10), end: at(23.5)), sun = MarathonDay(start: at(35), end: at(46))

    let over = MarathonPlan.plan(hp, days: [sat, sun], breakMinutes: 20, runOver: true)
    assert(over.days[0].count == 5, "five films on Saturday when the last may run over")
    assert(over.days[0].last!.overruns && over.days[0].last!.end == at(23.5 + 20.0 / 60), "Order of the Phoenix ends 23:50")
    assert(over.days[0][1].start == at(12 + 52.0 / 60), "second film starts after a 20 minute break")
    assert(over.days[1].count == 3 && over.left.isEmpty, "the rest on Sunday")

    let strict = MarathonPlan.plan(hp, days: [sat, sun], breakMinutes: 20, runOver: false)
    assert(strict.days[0].count == 4 && !strict.days[0].contains { $0.overruns }, "no overrun: the fifth moves to Sunday")
    assert(strict.days[1].count == 4 && strict.left.isEmpty)

    let tooLong = MarathonPlan.plan([film("x", 300)], days: [MarathonDay(start: at(20), end: at(22))], breakMinutes: 0, runOver: true)
    assert(tooLong.days[0].isEmpty && tooLong.left.count == 1, "a 5h film can't squeeze into a 2h evening, even running over")
    print("marathon checks passed")
}
