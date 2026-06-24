import Foundation

/// A catalog track confirmed available on Apple Music.
public struct CatalogMatch: Equatable {
    public let title: String
    public let artist: String
    public let appleMusicURL: URL
    /// Apple's free ~30s preview clip (DRM-free .m4a), used for on-device DSP feature extraction.
    public let previewUrl: URL?
    public init(title: String, artist: String, appleMusicURL: URL, previewUrl: URL? = nil) {
        self.title = title
        self.artist = artist
        self.appleMusicURL = appleMusicURL
        self.previewUrl = previewUrl
    }
}

/// Confirms a candidate exists on Apple Music. Injected as a fake in tests.
public protocol CatalogResolver {
    func resolve(artist: String, title: String) async -> CatalogMatch?
}

/// iTunes Search API resolver. Network `resolve` delegates to the pure `parse` for testability.
public struct iTunesResolver: CatalogResolver {
    public var session: URLSession
    public var limiter: RateLimiter

    /// The iTunes Search API rate-limits ~20 requests/min per IP (HTTP 429 past that). One process-
    /// wide limiter at ~3s/call keeps every resolve — interactive, pre-warm, and discover — under it.
    public static let sharedLimiter = RateLimiter(minInterval: .seconds(3))

    /// Default session with a finite request timeout so a stalled call fails fast instead of
    /// hanging on URLSession.shared's 60s default.
    public static let defaultSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    public init(session: URLSession = iTunesResolver.defaultSession,
                limiter: RateLimiter = iTunesResolver.sharedLimiter) {
        self.session = session
        self.limiter = limiter
    }

    public func resolve(artist: String, title: String) async -> CatalogMatch? {
        let term = "\(artist) \(title)"
        // limit=5, not 1: for collab tracks iTunes ranks the artist's top hit first, so the real
        // track is often further down. parse() then picks the title-matching result (or none).
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=5&term=\(q)")
        else { return nil }
        await limiter.acquire()   // stay under the iTunes rate limit (shared across all callers)
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.parse(data, artist: artist, title: title)
    }

    /// Picks the result whose track title matches the requested `title` (tolerating remix/feat.
    /// suffixes), breaking ties by artist overlap. Returns nil when nothing matches — better a miss
    /// than the artist's unrelated top hit, which would attach the wrong song's BPM/key.
    public static func parse(_ data: Data, artist: String, title: String) -> CatalogMatch? {
        struct Response: Decodable {
            struct Result: Decodable {
                let trackName: String; let artistName: String; let trackViewUrl: String
                let previewUrl: String?
            }
            let results: [Result]
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let wantTitle = normalize(title)
        let wantArtist = normalize(artist)
        guard !wantTitle.isEmpty else { return nil }

        let best = r.results
            .filter { titleMatches(normalize($0.trackName), wantTitle) }
            .max { artistOverlap(normalize($0.artistName), wantArtist) < artistOverlap(normalize($1.artistName), wantArtist) }

        guard let m = best, let url = URL(string: m.trackViewUrl) else { return nil }
        return CatalogMatch(title: m.trackName, artist: m.artistName, appleMusicURL: url,
                            previewUrl: m.previewUrl.flatMap(URL.init(string:)))
    }

    /// Lowercased, parentheticals/brackets stripped, reduced to alphanumeric words.
    private static func normalize(_ s: String) -> String {
        let noParens = s.lowercased().replacingOccurrences(of: #"[\(\[][^)\]]*[\)\]]"#,
                                                           with: " ", options: .regularExpression)
        let words = noParens.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(words).split(separator: " ").joined(separator: " ")
    }

    /// A candidate title matches if it equals the request, or either contains the other (so
    /// "Strobe (Original Mix)" → "strobe" still matches, and vice versa).
    private static func titleMatches(_ candidate: String, _ want: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        return candidate == want || candidate.contains(want) || want.contains(candidate)
    }

    /// Count of shared words between two normalized artist strings (tiebreaker only, never a gate).
    private static func artistOverlap(_ a: String, _ b: String) -> Int {
        let aw = Set(a.split(separator: " ")), bw = Set(b.split(separator: " "))
        return aw.intersection(bw).count
    }
}
