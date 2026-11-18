// Run: scripts/check.sh — decodes TMDB-shaped JSON through TitleDetail, Season and Person.
import Foundation
// Kept out of the check_*.swift bundle: TMDB.swift needs MainActor default isolation and a DateText stub.
enum DateText { static func isPast(_ s: String?) -> Bool { true } }
struct FilmFact { init(id: Int, name: String, year: Int?, countries: [String], director: String?, genres: [String]) {} }
let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
func j<T: Decodable>(_ s: String) -> T { try! dec.decode(T.self, from: s.data(using: .utf8)!) }

let movie: TitleDetail = j(#"{"id":1,"title":"Inception","original_title":"Inception","original_language":"en","release_date":"2010-07-15","budget":160000000,"revenue":0,"vote_count":37000,"genres":[],"production_countries":[{"iso_3166_1":"US","name":"United States of America"}],"production_companies":[{"id":1,"name":"Legendary","logo_path":null,"origin_country":"US"}],"release_dates":{"results":[{"iso_3166_1":"US","release_dates":[{"certification":"","type":1,"release_date":"x"},{"certification":"PG-13","type":3,"release_date":"x"}]},{"iso_3166_1":"FR","release_dates":[{"certification":"","type":3}]}]}}"#)
assert(movie.certifications == ["US": "PG-13"], "\(movie.certifications)")
assert(movie.budget == 160000000 && movie.revenue == nil && movie.voteCount == 37000)
assert(movie.countries == ["United States of America"] && movie.studios == ["Legendary"] && movie.years == "2010")

let show: TitleDetail = j(#"{"id":2,"name":"Breaking Bad","original_name":"Breaking Bad","first_air_date":"2008-01-20","last_air_date":"2013-09-29","status":"Ended","number_of_episodes":62,"networks":[{"id":1,"name":"AMC"}],"content_ratings":{"results":[{"descriptors":[],"iso_3166_1":"US","rating":"TV-MA"},{"iso_3166_1":"DE","rating":""}]}}"#)
assert(show.certifications == ["US": "TV-MA"] && show.years == "2008–2013" && show.networks == ["AMC"] && show.numberOfEpisodes == 62)
let running: TitleDetail = j(#"{"id":3,"name":"X","first_air_date":"2019-01-01","last_air_date":"2025-01-01","status":"Returning Series","content_ratings":"garbage"}"#)
assert(running.years == "2019–" && running.certifications.isEmpty)

let season: Season = j(#"{"episodes":[{"id":9,"season_number":5,"episode_number":16,"name":"Felina","overview":"","still_path":null,"air_date":"2013-09-29","runtime":55,"episode_type":"finale","vote_average":9.6,"vote_count":300,"crew":[{"id":1,"name":"Vince Gilligan","job":"Director","department":"Directing"},{"id":1,"name":"Vince Gilligan","job":"Writer"}],"guest_stars":[]}]}"#)
let e = season.episodes[0]
assert(e.milestone == "Season Finale" && e.credit(["Director"]) == "Vince Gilligan" && e.credit(["Writer"]) == "Vince Gilligan" && e.voteCount == 300)

let p: Person = j(#"{"id":17419,"name":"Bryan Cranston","biography":"","birthday":"1956-03-07","deathday":null,"place_of_birth":"Hollywood","known_for_department":"Acting","profile_path":"/a.jpg","combined_credits":{"cast":[{"id":1396,"media_type":"tv","name":"Breaking Bad","character":"Walter White","vote_count":15000,"genre_ids":[18]},{"id":22,"media_type":"tv","name":"Tonight Show","character":"Self - Guest","genre_ids":[10767]},{"id":23,"media_type":"tv","name":"Late Show","character":"","genre_ids":[10767]},{"id":5,"media_type":"movie","title":"Argo","character":"Jack O'Donnell","release_date":"2012-10-11"},{"id":6,"media_type":"movie","title":"Doc","character":"Himself"}],"crew":[{"id":1396,"media_type":"tv","name":"Breaking Bad","job":"Producer","genre_ids":[18]}]}}"#)
assert(p.biography == nil && p.credits.map(\.title.name) == ["Breaking Bad", "Argo", "Breaking Bad"], "\(p.credits.map(\.title.name))")
assert(p.credits[0].role == "Walter White" && p.credits[2].role == "Producer")
let odd: Season = j(#"{"episodes":[{"id":1,"season_number":1,"episode_number":1,"name":"Pilot","crew":"oops","vote_count":"many","episode_type":7}]}"#)
assert(odd.episodes.count == 1 && odd.episodes[0].crew == nil && odd.episodes[0].milestone == nil, "a bad extra mustn't lose the season")
let host: Person = j(#"{"id":1,"name":"Host","combined_credits":{"cast":[{"id":9,"media_type":"tv","name":"Late Show","character":"Self - Host","genre_ids":[10767]}]}}"#)
assert(host.credits.count == 1, "all appearances: keep them rather than an empty page")
print("tmdb decode checks passed")
