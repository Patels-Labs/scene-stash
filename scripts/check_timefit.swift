// Run: scripts/check.sh — asserts what fits in an evening in TimeFit.swift.
do {
    let fits = TimeFit.fits([[122], [45, 45, 45], [200], [30, 60]], minutes: 90)
    assert(fits.map(\.index) == [1, 3], "the 2h film and the 3h20 film don't fit 90 minutes")
    assert(fits[0] == .init(index: 1, count: 2, used: 90, spare: 0), "two episodes, on the dot")
    assert(fits[1] == .init(index: 3, count: 2, used: 90, spare: 0), "ties keep their order")
    assert(TimeFit.fits([[60, 10]], minutes: 50).isEmpty, "episodes play in order, so a short second one can't jump the queue")
    assert(TimeFit.fits([[94]], minutes: 120) == [.init(index: 0, count: 1, used: 94, spare: 26)])
    print("time fit checks passed")
}
