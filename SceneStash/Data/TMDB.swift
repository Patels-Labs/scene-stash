import Foundation

nonisolated enum MediaType: String, Codable, Hashable, Sendable {
    case movie, tv, person
    /// A film series. Only used for its page and artwork; TMDB's paths for it start "collection/".
    case collection
}

/// A movie or show as it appears in lists, search and trending.
nonisolated struct Title: Decodable, Hashable, Sendable {
    let id: Int
    let mediaType: MediaType
    let name: String
    let posterPath: String?
    let backdropPath: String?
    let overview: String
    let date: String?
    let voteAverage: Double?

    var year: String? { date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
    /// Has a release date still to come. No date (many saved titles carry none) counts as out.
    @MainActor var unreleased: Bool { date.map { !DateText.isPast($0) } ?? false }

    private enum CodingKeys: String, CodingKey {
        case id, mediaType, title, name, posterPath, backdropPath, overview, releaseDate, firstAirDate, voteAverage
    }

    init(id: Int, mediaType: MediaType, name: String, posterPath: String?, backdropPath: String? = nil,
         overview: String = "", date: String? = nil, voteAverage: Double? = nil) {
        self.id = id; self.mediaType = mediaType; self.name = name; self.posterPath = posterPath
        self.backdropPath = backdropPath; self.overview = overview; self.date = date; self.voteAverage = voteAverage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        let movieTitle = try c.decodeIfPresent(String.self, forKey: .title)
        // Trending/search carry media_type; typed endpoints don't, but movies have `title` and shows `name`.
        mediaType = try c.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? (movieTitle != nil ? .movie : .tv)
        name = try movieTitle ?? c.decodeIfPresent(String.self, forKey: .name) ?? ""
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        let d = try c.decodeIfPresent(String.self, forKey: .releaseDate) ?? c.decodeIfPresent(String.self, forKey: .firstAirDate)
        date = d?.isEmpty == true ? nil : d
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
    }
}

nonisolated struct Page<T: Decodable & Sendable>: Decodable, Sendable { let results: [T] }

nonisolated struct Genre: Decodable, Hashable, Sendable { let id: Int; let name: String }

nonisolated struct SeasonSummary: Decodable, Hashable, Sendable {
    let seasonNumber: Int
    let episodeCount: Int
    let name: String
    let posterPath: String?
    let airDate: String?
}

nonisolated struct Episode: Decodable, Hashable, Sendable {
    let id: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let runtime: Int?
    var guestStars: [CastMember]? = nil
    /// Only in a season's listing: who directed and wrote it, its score, and whether it ends a season.
    var crew: [CrewMember]? = nil
    var voteAverage: Double? = nil
    var voteCount: Int? = nil
    var episodeType: String? = nil

    /// "Season Finale", "Mid-Season Finale", or nil for a regular episode.
    var milestone: String? {
        switch episodeType {
        case "finale": "Season Finale"
        case "mid_season": "Mid-Season Finale"
        default: nil
        }
    }

    /// Up to two names for any of `jobs`, e.g. "Vince Gilligan & Peter Gould".
    func credit(_ jobs: Set<String>) -> String? {
        var seen = Set<Int>()
        let names = (crew ?? []).filter { jobs.contains($0.job ?? "") && seen.insert($0.id).inserted }.prefix(2).map(\.name)
        return names.isEmpty ? nil : names.joined(separator: " & ")
    }
}

nonisolated extension Episode {
    private enum CodingKeys: String, CodingKey {
        case id, seasonNumber, episodeNumber, name, overview, stillPath, airDate, runtime, guestStars, crew, voteAverage, voteCount, episodeType
    }
    /// In an extension so the memberwise init survives. The extras are `try?`: a bad one mustn't lose the whole season.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(Int.self, forKey: .id), seasonNumber: try c.decode(Int.self, forKey: .seasonNumber),
                  episodeNumber: try c.decode(Int.self, forKey: .episodeNumber), name: try c.decode(String.self, forKey: .name),
                  overview: try c.decodeIfPresent(String.self, forKey: .overview), stillPath: try c.decodeIfPresent(String.self, forKey: .stillPath),
                  airDate: try c.decodeIfPresent(String.self, forKey: .airDate), runtime: try c.decodeIfPresent(Int.self, forKey: .runtime),
                  guestStars: try c.decodeIfPresent([CastMember].self, forKey: .guestStars))
        crew = (try? c.decodeIfPresent([CrewMember].self, forKey: .crew)) ?? nil
        voteAverage = (try? c.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
        voteCount = (try? c.decodeIfPresent(Int.self, forKey: .voteCount)) ?? nil
        episodeType = (try? c.decodeIfPresent(String.self, forKey: .episodeType)) ?? nil
    }
}

nonisolated struct CrewMember: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let job: String?
}

nonisolated struct Season: Decodable, Sendable { let episodes: [Episode] }

nonisolated struct CastMember: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}

/// Someone in the cast or crew, with everything they've been in.
nonisolated struct Person: Decodable, Sendable {
    let id: Int
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profilePath: String?
    /// Acting roles first, then crew jobs; talk shows and appearances as themselves left out.
    let credits: [Credit]

    nonisolated struct Credit: Decodable, Hashable, Sendable {
        let title: Title
        /// The character played, or the job done.
        let role: String?
        let votes: Int
        private let genreIds: [Int]?

        private enum CodingKeys: String, CodingKey { case character, job, voteCount, genreIds }
        init(from decoder: Decoder) throws {
            title = try Title(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let character = try c.decodeIfPresent(String.self, forKey: .character).flatMap { $0.isEmpty ? nil : $0 }
            role = try character ?? c.decodeIfPresent(String.self, forKey: .job)
            votes = try c.decodeIfPresent(Int.self, forKey: .voteCount) ?? 0
            genreIds = try c.decodeIfPresent([Int].self, forKey: .genreIds)
        }

        /// Talk and news shows (TMDB's TV genres 10767, 10763), and anything where they play themselves.
        var isAppearance: Bool {
            if title.mediaType == .tv, genreIds?.contains(where: { $0 == 10767 || $0 == 10763 }) == true { return true }
            let r = role?.lowercased() ?? ""
            return r.hasPrefix("self") || ["himself", "herself", "themselves", "themself"].contains { r.contains($0) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday, placeOfBirth, knownForDepartment, profilePath, combinedCredits
    }
    private struct Combined: Decodable { let cast: [Credit]?; let crew: [Credit]? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } }
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        biography = text(.biography)
        birthday = text(.birthday)
        deathday = text(.deathday)
        placeOfBirth = text(.placeOfBirth)
        knownForDepartment = text(.knownForDepartment)
        profilePath = text(.profilePath)
        let combined = (try? c.decodeIfPresent(Combined.self, forKey: .combinedCredits)) ?? nil
        let all = ((combined?.cast ?? []) + (combined?.crew ?? [])).filter { $0.title.mediaType != .person }
        let roles = all.filter { !$0.isAppearance }
        // A presenter or host may have nothing but appearances; better those than an empty page.
        credits = roles.isEmpty ? all : roles
    }
}

nonisolated struct Video: Decodable, Sendable { let key: String; let site: String; let type: String }

nonisolated struct Provider: Decodable, Hashable, Sendable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    /// The service's own search for a title, so a tap lands in its app (or site) rather than on TMDB.
    /// TMDB doesn't give per-service links; unknown services return nil and fall back to TMDB's page.
    func searchURL(for title: String) -> URL? {
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let name = providerName.lowercased()
        // Channels sold through another store open in that store, so check those first.
        let search: [(String, String)] = [
            ("amazon", "https://www.primevideo.com/search?phrase="), ("prime video", "https://www.primevideo.com/search?phrase="),
            ("apple tv", "https://tv.apple.com/search?term="), ("netflix", "https://www.netflix.com/search?q="),
            ("disney", "https://www.disneyplus.com/search?q="), ("paramount", "https://www.paramountplus.com/search/?q="),
            ("hulu", "https://www.hulu.com/search?q="), ("peacock", "https://www.peacocktv.com/search?q="),
            ("max", "https://play.max.com/search?q="), ("crunchyroll", "https://www.crunchyroll.com/search?q="),
            ("iplayer", "https://www.bbc.co.uk/iplayer/search?q="), ("itvx", "https://www.itv.com/watch/search?q="),
            ("channel 4", "https://www.channel4.com/search?q="), ("now", "https://www.nowtv.com/search?q="),
        ]
        return search.first { name.hasPrefix($0.0) || name.contains(" \($0.0)") || name.contains($0.0 + " ") }.flatMap { URL(string: $0.1 + q) }
    }
}

nonisolated struct RegionProviders: Decodable, Sendable {
    let link: String?
    let flatrate: [Provider]?
    let rent: [Provider]?
    let buy: [Provider]?
}

nonisolated struct Region: Decodable, Hashable, Sendable {
    let iso31661: String
    let englishName: String
}

nonisolated struct TitleDetail: Decodable, Sendable {
    let id: Int
    let mediaType: MediaType
    let name: String
    let tagline: String?
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let date: String?
    let runtime: Int?
    let genres: [Genre]
    let voteAverage: Double?
    let status: String?
    let seasons: [SeasonSummary]
    let lastEpisodeToAir: Episode?
    let nextEpisodeToAir: Episode?
    let cast: [CastMember]
    /// Poster-style credits: director, top billing, music and photography, in one run-on line.
    let billing: [(role: String?, name: String)]
    let trailerURL: URL?
    let providers: [String: RegionProviders]
    let recommendations: [Title]
    /// Scenes during or after the credits, from TMDB's community keywords (so absence isn't proof).
    let midCredits: Bool
    let afterCredits: Bool
    /// The film series this belongs to, for planning a marathon of the lot.
    let collection: (id: Int, name: String, poster: String?, backdrop: String?)?
    let voteCount: Int?
    /// Age rating by country code ("US": "PG-13"), only where one is set.
    let certifications: [String: String]
    let networks: [String]
    let numberOfEpisodes: Int?
    let lastAirDate: String?
    /// TMDB uses 0 for unknown money; those come through as nil.
    let budget: Int?
    let revenue: Int?
    let originalTitle: String?
    let originalLanguage: String?
    let countries: [String]
    let studios: [String]

    var year: String? { date.map { String($0.prefix(4)) } }
    /// "2008–2013" for a show that's finished, "2019–" for one still going, the year for a film.
    var years: String? {
        guard let start = year else { return nil }
        guard mediaType == .tv else { return start }
        // A running show's last air date is just its latest episode, so the range stays open.
        guard status == "Ended" || status == "Canceled", let end = lastAirDate.map({ String($0.prefix(4)) }) else { return "\(start)–" }
        return end == start ? start : "\(start)–\(end)"
    }
    /// Seasons that count toward progress (specials excluded).
    var mainSeasons: [SeasonSummary] { seasons.filter { $0.seasonNumber > 0 && $0.episodeCount > 0 } }
    var title: Title { Title(id: id, mediaType: mediaType, name: name, posterPath: posterPath, backdropPath: backdropPath, overview: overview, date: date, voteAverage: voteAverage) }

    private enum CodingKeys: String, CodingKey {
        case id, title, name, tagline, overview, posterPath, backdropPath, releaseDate, firstAirDate
        case runtime, episodeRunTime, genres, voteAverage, status, seasons, lastEpisodeToAir, nextEpisodeToAir
        case credits, videos, recommendations, createdBy, keywords, belongsToCollection
        case voteCount, releaseDates, contentRatings, networks, numberOfEpisodes, lastAirDate, budget, revenue
        case originalTitle, originalName, originalLanguage, productionCountries, productionCompanies
        case watchProviders = "watch/providers"
    }
    private struct Named: Decodable { let name: String }
    /// Films carry certifications per release (`release_dates`), shows one rating per country (`content_ratings`).
    private struct Ratings: Decodable {
        struct Release: Decodable { let certification: String?; let type: Int? }
        struct Country: Decodable { let iso31661: String; let rating: String?; let releaseDates: [Release]? }
        let results: [Country]
    }
    private struct Crew: Decodable { let name: String; let job: String? }
    private struct Credits: Decodable { let cast: [CastMember]; let crew: [Crew]? }
    private struct Series: Decodable { let id: Int; let name: String; let posterPath: String?; let backdropPath: String? }
    private struct Providers: Decodable { let results: [String: RegionProviders] }
    /// Films nest keywords under `keywords`, shows under `results`.
    private struct Keywords: Decodable {
        struct Keyword: Decodable { let id: Int }
        let keywords: [Keyword]?
        let results: [Keyword]?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        let movieTitle = try c.decodeIfPresent(String.self, forKey: .title)
        mediaType = movieTitle != nil ? .movie : .tv
        name = try movieTitle ?? c.decode(String.self, forKey: .name)
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline).flatMap { $0.isEmpty ? nil : $0 }
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        let d = try c.decodeIfPresent(String.self, forKey: .releaseDate) ?? c.decodeIfPresent(String.self, forKey: .firstAirDate)
        date = d?.isEmpty == true ? nil : d
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime) ?? c.decodeIfPresent([Int].self, forKey: .episodeRunTime)?.first
        genres = try c.decodeIfPresent([Genre].self, forKey: .genres) ?? []
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        seasons = try c.decodeIfPresent([SeasonSummary].self, forKey: .seasons) ?? []
        lastEpisodeToAir = try c.decodeIfPresent(Episode.self, forKey: .lastEpisodeToAir)
        nextEpisodeToAir = try c.decodeIfPresent(Episode.self, forKey: .nextEpisodeToAir)
        let credits = try c.decodeIfPresent(Credits.self, forKey: .credits)
        cast = credits?.cast ?? []
        let crew = credits?.crew ?? []
        func people(_ job: String) -> String? {
            let names = crew.filter { $0.job == job }.map(\.name).prefix(2)
            return names.isEmpty ? nil : names.joined(separator: " & ")
        }
        let creators = (try? c.decodeIfPresent([Crew].self, forKey: .createdBy))?.map(\.name).prefix(2).joined(separator: " & ")
        var bill: [(String?, String)] = []
        if let d = people("Director") { bill.append(("Directed by", d)) } else if let creators, !creators.isEmpty { bill.append(("Created by", creators)) }
        bill += cast.prefix(7).map { (nil, $0.name) }
        if let m = people("Original Music Composer") { bill.append(("Music by", m)) }
        if let p = people("Director of Photography") { bill.append(("Photography", p)) }
        if let w = people("Screenplay") ?? people("Writer") { bill.append(("Written by", w)) }
        billing = bill
        let videos = try c.decodeIfPresent(Page<Video>.self, forKey: .videos)?.results ?? []
        trailerURL = (videos.first { $0.site == "YouTube" && $0.type == "Trailer" } ?? videos.first { $0.site == "YouTube" })
            .flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
        providers = try c.decodeIfPresent(Providers.self, forKey: .watchProviders)?.results ?? [:]
        recommendations = (try? c.decodeIfPresent(Page<Title>.self, forKey: .recommendations)?.results) ?? []
        let tags = (try? c.decodeIfPresent(Keywords.self, forKey: .keywords)).flatMap { $0?.keywords ?? $0?.results } ?? []
        collection = (try? c.decodeIfPresent(Series.self, forKey: .belongsToCollection)).flatMap { $0 }.map { ($0.id, $0.name, $0.posterPath, $0.backdropPath) }
        midCredits = tags.contains { $0.id == 179431 } // "duringcreditsstinger"
        afterCredits = tags.contains { $0.id == 179430 } // "aftercreditsstinger"

        // Extras: none of these is worth failing the page over.
        func optional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? { (try? c.decodeIfPresent(type, forKey: key)) ?? nil }
        func names(_ key: CodingKeys) -> [String] { optional([Named].self, key)?.map(\.name) ?? [] }
        func known(_ key: CodingKeys) -> Int? { optional(Int.self, key).flatMap { $0 > 0 ? $0 : nil } }
        voteCount = known(.voteCount)
        var certs: [String: String] = [:]
        for country in (optional(Ratings.self, .releaseDates) ?? optional(Ratings.self, .contentRatings))?.results ?? [] {
            // A film's theatrical rating first; other releases only if that's blank.
            let releases = (country.releaseDates ?? []).sorted { ($0.type == 3 ? 0 : 1) < ($1.type == 3 ? 0 : 1) }.compactMap(\.certification)
            if let rating = ([country.rating].compactMap { $0 } + releases).first(where: { !$0.isEmpty }) { certs[country.iso31661] = rating }
        }
        certifications = certs
        networks = names(.networks)
        numberOfEpisodes = known(.numberOfEpisodes)
        lastAirDate = optional(String.self, .lastAirDate).flatMap { $0.isEmpty ? nil : $0 }
        budget = known(.budget)
        revenue = known(.revenue)
        originalTitle = optional(String.self, .originalTitle) ?? optional(String.self, .originalName)
        originalLanguage = optional(String.self, .originalLanguage)
        countries = names(.productionCountries)
        studios = names(.productionCompanies)
    }
}

/// A horizontal row of titles on Discover.
nonisolated struct Reel: Hashable {
    let name: String
    let path: String
    var query: [String: String] = [:]
    var caption: String? = nil
}

extension Reel {
    static let featured = Reel(name: "Trending", path: "trending/all/week")
    /// Search's Browse tiles.
    static let browse: [Reel] = [
        Reel(name: "In Cinemas Now", path: "movie/now_playing"),
        Reel(name: "Coming Soon", path: "movie/upcoming"),
        Reel(name: "Top TV", path: "tv/top_rated"),
        Reel(name: "Sci-Fi & Mystery", path: "discover/movie", query: ["with_genres": "878|9648", "sort_by": "vote_count.desc"]),
        Reel(name: "Horror", path: "discover/movie", query: ["with_genres": "27", "sort_by": "popularity.desc"]),
        Reel(name: "Comedy", path: "discover/tv", query: ["with_genres": "35", "sort_by": "popularity.desc"]),
        Reel(name: "Crime", path: "discover/tv", query: ["with_genres": "80", "sort_by": "popularity.desc"]),
        Reel(name: "Animation", path: "discover/tv", query: ["with_genres": "16", "sort_by": "popularity.desc"]),
        // TMDB's community keywords for scenes during and after the credits.
        Reel(name: "After-Credits Scenes", path: "discover/movie", query: ["with_keywords": "179430|179431", "sort_by": "popularity.desc"]),
    ]
}

enum ImageSize: String {
    case poster = "w342", posterLarge = "w500", hero = "w780", backdrop = "w1280", original = "original", still = "w300", profile = "w185", logo = "w92"
    /// The largest profile size TMDB lists short of the original, for a person's page.
    case portrait = "h632"
}

enum TMDBError: LocalizedError {
    case missingToken, http(Int)
    var errorDescription: String? {
        switch self {
        case .missingToken: "The TMDB token is missing from this build."
        case .http(let code): "TMDB returned an error (\(code))."
        }
    }
}

final class TMDB {
    static let shared = TMDB()

    private let token = (Bundle.main.object(forInfoDictionaryKey: "TMDBToken") as? String) ?? ""
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 100 << 20)
        return URLSession(configuration: config)
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func imageURL(_ path: String?, _ size: ImageSize) -> URL? {
        path.flatMap { URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\($0)") }
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        guard !token.isEmpty else { throw TMDBError.missingToken }
        var comps = URLComponents(string: "https://api.themoviedb.org/3/\(path)")!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TMDBError.http(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    func titles(_ reel: Reel) async throws -> [Title] {
        let page: Page<Title> = try await get(reel.path, reel.query)
        return page.results.filter { $0.mediaType != .person && $0.posterPath != nil }
    }

    func search(_ text: String) async throws -> [Title] {
        let page: Page<Title> = try await get("search/multi", ["query": text, "include_adult": "false"])
        return page.results.filter { $0.mediaType != .person }
    }

    func detail(_ id: Int, _ type: MediaType) async throws -> TitleDetail {
        let ratings = type == .movie ? "release_dates" : "content_ratings"
        return try await get("\(type.rawValue)/\(id)", ["append_to_response": "credits,videos,watch/providers,recommendations,keywords,\(ratings)"])
    }

    func person(_ id: Int) async throws -> Person {
        try await get("person/\(id)", ["append_to_response": "combined_credits"])
    }

    func season(show: Int, number: Int) async throws -> Season {
        try await get("tv/\(show)/season/\(number)")
    }

    func providers(region: String) async throws -> [Provider] {
        async let movie: Page<Provider> = get("watch/providers/movie", ["watch_region": region])
        async let tv: Page<Provider> = get("watch/providers/tv", ["watch_region": region])
        var seen = Set<Int>()
        return try await (movie.results + tv.results)
            .sorted { ($0.displayPriority ?? 999) < ($1.displayPriority ?? 999) }
            .filter { seen.insert($0.providerId).inserted }
    }

    nonisolated struct Series: Decodable, Sendable {
        let name: String
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let parts: [Title]
    }

    /// A film series, its parts in release order with unreleased ones left out.
    func series(_ id: Int) async throws -> Series {
        let s: Series = try await get("collection/\(id)")
        return Series(name: s.name, overview: s.overview, posterPath: s.posterPath, backdropPath: s.backdropPath,
                      parts: s.parts.filter { DateText.isPast($0.date) }.sorted { ($0.date ?? "") < ($1.date ?? "") })
    }

    /// What a film adds to the passport: its year, countries, director and genres.
    func fact(_ id: Int) async -> FilmFact? {
        struct Named: Decodable { let name: String }
        struct Crew: Decodable { let name: String; let job: String? }
        struct Credits: Decodable { let crew: [Crew] }
        struct Raw: Decodable { let title: String; let releaseDate: String?; let productionCountries: [Named]?; let genres: [Named]?; let credits: Credits? }
        guard let r: Raw = try? await get("movie/\(id)", ["append_to_response": "credits"]) else { return nil }
        return FilmFact(id: id, name: r.title, year: r.releaseDate.flatMap { Int($0.prefix(4)) }, countries: r.productionCountries?.map(\.name) ?? [],
                        director: r.credits?.crew.first { $0.job == "Director" }?.name, genres: r.genres?.map(\.name) ?? [])
    }

    /// Just a film's running time, without everything else on its page.
    func runtime(_ id: Int) async -> Int? {
        let d: TitleDetail? = try? await get("movie/\(id)")
        return d?.runtime
    }

    /// Artwork for the top of a title's page: its logo in English (or with no text), and a poster with no
    /// text on it so the logo isn't printed twice. Remembered per title.
    struct Artwork: Sendable { let logo: String?; let poster: String? }
    func artwork(_ id: Int, _ type: MediaType) async -> Artwork {
        let key = "\(type.rawValue)/\(id)"
        if let hit = artworks[key] { return hit }
        struct Images: Decodable {
            struct Image: Decodable { let filePath: String; let iso6391: String? }
            // Collections have no logos, so the key is missing rather than empty.
            let logos: [Image]?; let posters: [Image]?
        }
        let images: Images? = try? await get("\(key)/images", ["include_image_language": "en,null"])
        let logo = images?.logos?.first { $0.iso6391 == "en" }?.filePath ?? images?.logos?.first?.filePath
        let art = Artwork(logo: logo, poster: images?.posters?.first { $0.iso6391 == nil }?.filePath)
        artworks[key] = art
        return art
    }
    private var artworks: [String: Artwork] = [:]

    func regions() async throws -> [Region] {
        let page: Page<Region> = try await get("watch/providers/regions")
        return page.results.sorted { $0.englishName < $1.englishName }
    }
}
