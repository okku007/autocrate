import Foundation
import os

/// Supplies features for a track. Always returns a CachedFeature (state .found or .miss),
/// so the hydrator can persist every outcome. Injected as a fake in tests.
public protocol FeatureProvider {
    func lookup(artist: String, title: String, id: String) async -> CachedFeature
}

/// GetSongBPM-backed provider.
///
/// NOTE: the base host and exact JSON shape (`search` wrapper, `tempo`, `key_of`) must be
/// confirmed against one real API response before being trusted; adjust the decode types if
/// they differ. `KeyToCamelot` is the source of truth for the Camelot value.
public struct GetSongBpmClient: FeatureProvider {
    public let apiKey: String
    public var session: URLSession
    private let log = Logger(subsystem: "dev.moksh.autocrate", category: "getsongbpm")

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        let now = Int(Date().timeIntervalSince1970)
        func miss() -> CachedFeature {
            CachedFeature(id: id, title: title, artist: artist, bpm: nil, camelot: nil,
                          musicalKey: nil, source: "getsongbpm", state: .miss, fetchedAt: now)
        }
        guard let song = await search(artist: artist, title: title) else { return miss() }

        let bpm = song.tempo.flatMap(Double.init)
        let camelot = song.keyOf.flatMap { KeyToCamelot.camelot(forMusicalKey: $0) }?.description
        guard bpm != nil || camelot != nil else { return miss() }

        return CachedFeature(id: id, title: title, artist: artist, bpm: bpm, camelot: camelot,
                             musicalKey: song.keyOf, source: "getsongbpm", state: .found, fetchedAt: now)
    }

    // MARK: - Network

    private struct SearchResponse: Decodable { let search: [Song]? }
    private struct Song: Decodable {
        let tempo: String?
        let keyOf: String?
        enum CodingKeys: String, CodingKey { case tempo; case keyOf = "key_of" }
    }

    private func search(artist: String, title: String) async -> Song? {
        let lookup = "song:\(title) artist:\(artist)"
        guard let q = lookup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.getsong.co/search/?api_key=\(apiKey)&type=both&lookup=\(q)")
        else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SearchResponse.self, from: data).search?.first
        } catch {
            log.error("search failed: \(error.localizedDescription)")
            return nil
        }
    }
}
