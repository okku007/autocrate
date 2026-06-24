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

    /// Catalog discovery: GetSongBPM `/tempo/` + `/key/` search for fresh candidates
    /// (not necessarily in the user's library). Genre is unknown here (nil).
    ///
    /// NOTE: the `/tempo/` and `/key/` response shapes must be confirmed against a live call;
    /// adjust the decode types to match.
    public func discover(targetBPM: Double, camelot: CamelotKey) async -> [Track] {
        async let byTempo = searchList(path: "tempo", paramName: "bpm", value: String(format: "%.0f", targetBPM))
        async let byKey   = searchList(path: "key",   paramName: "key", value: camelot.description)
        let combined = await byTempo + byKey
        var seen = Set<String>()
        var out: [Track] = []
        for t in combined where seen.insert(t.id).inserted { out.append(t) }
        return out
    }

    private struct DiscoverItem: Decodable {
        let tempo: String?
        let keyOf: String?
        let songTitle: String?
        let artist: Artist?
        struct Artist: Decodable { let name: String? }
        enum CodingKeys: String, CodingKey {
            case tempo
            case keyOf = "key_of"
            case songTitle = "song_title"
            case artist
        }
    }
    private struct DiscoverResponse: Decodable {
        let tempo: [DiscoverItem]?
        let key: [DiscoverItem]?
    }

    private func searchList(path: String, paramName: String, value: String) async -> [Track] {
        guard let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.getsong.co/\(path)/?api_key=\(apiKey)&\(paramName)=\(v)")
        else { return [] }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(DiscoverResponse.self, from: data)
        else { return [] }

        let items = (decoded.tempo ?? []) + (decoded.key ?? [])
        return items.compactMap { item in
            guard let title = item.songTitle, let artist = item.artist?.name else { return nil }
            return Track(
                id: "\(artist.lowercased().trimmingCharacters(in: .whitespaces))|\(title.lowercased().trimmingCharacters(in: .whitespaces))",
                title: title, artist: artist, genre: nil,
                bpm: item.tempo.flatMap(Double.init),
                camelot: item.keyOf.flatMap { KeyToCamelot.camelot(forMusicalKey: $0) }
            )
        }
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
