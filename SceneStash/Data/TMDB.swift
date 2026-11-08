import Foundation

nonisolated enum MediaType: String, Codable, Hashable, Sendable {
    case movie, tv, person
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
}

nonisolated struct Season: Decodable, Sendable { let episodes: [Episode] }

nonisolated struct CastMember: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
}

nonisolated struct Video: Decodable, Sendable { let key: String; let site: String; let type: String }

nonisolated struct Provider: Decodable, Hashable, Sendable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?
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
    let collection: (id: Int, name: String)?

    var year: String? { date.map { String($0.prefix(4)) } }
    /// Seasons that count toward progress (specials excluded).
    var mainSeasons: [SeasonSummary] { seasons.filter { $0.seasonNumber > 0 && $0.episodeCount > 0 } }
    var title: Title { Title(id: id, mediaType: mediaType, name: name, posterPath: posterPath, backdropPath: backdropPath, overview: overview, date: date, voteAverage: voteAverage) }

    private enum CodingKeys: String, CodingKey {
        case id, title, name, tagline, overview, posterPath, backdropPath, releaseDate, firstAirDate
        case runtime, episodeRunTime, genres, voteAverage, status, seasons, lastEpisodeToAir, nextEpisodeToAir
        case credits, videos, recommendations, createdBy, keywords, belongsToCollection
        case watchProviders = "watch/providers"
    }
    private struct Crew: Decodable { let name: String; let job: String? }
    private struct Credits: Decodable { let cast: [CastMember]; let crew: [Crew]? }
    private struct Series: Decodable { let id: Int; let name: String }
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
        collection = (try? c.decodeIfPresent(Series.self, forKey: .belongsToCollection)).flatMap { $0 }.map { ($0.id, $0.name) }
        midCredits = tags.contains { $0.id == 179431 } // "duringcreditsstinger"
        afterCredits = tags.contains { $0.id == 179430 } // "aftercreditsstinger"
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
    static let featured = Reel(name: "Trending this week", path: "trending/all/week")
    static let discover: [Reel] = [
        Reel(name: "Now in cinemas", path: "movie/now_playing", caption: "On the big screen"),
        Reel(name: "Bingeable", path: "tv/top_rated", caption: "Clear your weekend"),
        Reel(name: "Mind benders", path: "discover/movie", query: ["with_genres": "878|9648", "sort_by": "vote_count.desc"], caption: "Sci-fi & mystery"),
        Reel(name: "Lights off", path: "discover/movie", query: ["with_genres": "27", "sort_by": "popularity.desc"], caption: "Horror"),
        Reel(name: "Animated worlds", path: "discover/tv", query: ["with_genres": "16", "sort_by": "popularity.desc"], caption: "Animation"),
        Reel(name: "Laugh track", path: "discover/tv", query: ["with_genres": "35", "sort_by": "popularity.desc"], caption: "Comedy"),
        Reel(name: "Crime nights", path: "discover/tv", query: ["with_genres": "80", "sort_by": "popularity.desc"], caption: "Crime"),
    ]
}

enum ImageSize: String {
    case poster = "w342", posterLarge = "w500", hero = "w780", backdrop = "w1280", still = "w300", profile = "w185", logo = "w92"
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
        try await get("\(type.rawValue)/\(id)", ["append_to_response": "credits,videos,watch/providers,recommendations,keywords"])
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

    /// A film series' parts in release order, unreleased ones left out.
    func collection(_ id: Int) async throws -> [Title] {
        struct Collection: Decodable { let parts: [Title] }
        let c: Collection = try await get("collection/\(id)")
        return c.parts.filter { DateText.isPast($0.date) }.sorted { ($0.date ?? "") < ($1.date ?? "") }
    }

    /// A title's logo artwork in English (or with no text), for the top of its page. Remembered per title.
    func logo(_ id: Int, _ type: MediaType) async -> String? {
        let key = "\(type.rawValue)/\(id)"
        if let hit = logos[key] { return hit }
        struct Images: Decodable { struct Image: Decodable { let filePath: String; let iso6391: String? }; let logos: [Image] }
        let images: Images? = try? await get("\(key)/images", ["include_image_language": "en,null"])
        let path = images?.logos.first { $0.iso6391 == "en" }?.filePath ?? images?.logos.first?.filePath
        logos[key] = .some(path)
        return path
    }
    private var logos: [String: String?] = [:]

    func regions() async throws -> [Region] {
        let page: Page<Region> = try await get("watch/providers/regions")
        return page.results.sorted { $0.englishName < $1.englishName }
    }
}
