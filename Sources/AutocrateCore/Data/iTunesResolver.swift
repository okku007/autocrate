import Foundation

/// A catalog track confirmed available on Apple Music.
public struct CatalogMatch: Equatable {
    public let title: String
    public let artist: String
    public let appleMusicURL: URL
    public init(title: String, artist: String, appleMusicURL: URL) {
        self.title = title
        self.artist = artist
        self.appleMusicURL = appleMusicURL
    }
}

/// Confirms a candidate exists on Apple Music. Injected as a fake in tests.
public protocol CatalogResolver {
    func resolve(artist: String, title: String) async -> CatalogMatch?
}

/// iTunes Search API resolver. Network `resolve` delegates to the pure `parse` for testability.
public struct iTunesResolver: CatalogResolver {
    public var session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func resolve(artist: String, title: String) async -> CatalogMatch? {
        let term = "\(artist) \(title)"
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=1&term=\(q)")
        else { return nil }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.parse(data)
    }

    public static func parse(_ data: Data) -> CatalogMatch? {
        struct Response: Decodable {
            struct Result: Decodable { let trackName: String; let artistName: String; let trackViewUrl: String }
            let results: [Result]
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let first = r.results.first, let url = URL(string: first.trackViewUrl) else { return nil }
        return CatalogMatch(title: first.trackName, artist: first.artistName, appleMusicURL: url)
    }
}
