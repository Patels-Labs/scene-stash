// Run: scripts/check.sh — asserts how stamps are earned in Passport.swift.
do {
    let day: (Int) -> Date = { Date(timeIntervalSince1970: TimeInterval($0) * 86_400) }
    let film: (Int, Int, String, String?) -> FilmFact = { FilmFact(id: $0, name: "F\($0)", year: $1, countries: [$2], director: $3, genres: ["Horror"]) }
    let watched = (1...12).map { (film($0, 1970 + $0 % 3, $0 == 4 ? "South Korea" : "United States", $0 <= 3 ? "Villeneuve" : nil), day(13 - $0)) }
    let stamps = Passport.stamps(watched)
    let find: (Passport.Stamp.Kind, String) -> Passport.Stamp? = { k, n in stamps.first { $0.kind == k && $0.name == n } }
    assert(find(.country, "South Korea")?.earnedOn == day(9), "one film earns a country")
    assert(find(.director, "Villeneuve")?.earnedOn == day(12), "earned by the third of them in watch order")
    assert(find(.genre, "Horror")?.earned == true && find(.genre, "Horror")?.films.count == 12)
    assert(find(.decade, "The '70s")?.films.count == 12)
    assert(find(.milestone, "10 Films")?.earned == true)
    assert(find(.milestone, "25 Films")?.earned == false, "the next milestone shows, locked")
    assert(find(.milestone, "50 Films") == nil, "and only the next one")
    assert(Passport.decade(2014) == "The 2010s" && Passport.decade(1999) == "The '90s" && Passport.decade(1905) == "The '00s")
    print("passport checks passed")
}
