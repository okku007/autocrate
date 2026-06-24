import Foundation
import AutocrateCore

/// Every state the panel can render.
public enum PanelState: Equatable {
    case loading
    case nothingPlaying
    case permissionDenied
    case seedMiss(Track)
    case noMatches(Track)
    case indexing(seed: Track, shown: [ScoredCandidate], total: Int, hydrated: Int)
    case ready(seed: Track, matches: [ScoredCandidate], discover: [ScoredCandidate])
}

/// Coordinates now-playing → hydrate → filter → discover into a single PanelState.
@MainActor
public final class MatchEngine: ObservableObject {
    @Published public private(set) var state: PanelState = .loading

    private let nowPlaying = NowPlayingReader()
    private let library = LibraryReader()
    private let pipeline = CandidatePipeline()
    private let cache: FeatureCache
    private let hydrator: FeatureHydrator
    private let apiKey: String

    public init() {
        let cache = try! FeatureCache(path: Self.defaultCachePath())
        self.cache = cache
        self.apiKey = Secrets.getSongBpmApiKey
        self.hydrator = FeatureHydrator(
            cache: cache,
            provider: GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey)
        )
    }

    public func refresh() async {
        state = .loading
        switch nowPlaying.read() {
        case .permissionDenied:
            state = .permissionDenied
        case .stopped:
            state = .nothingPlaying
        case .playing(let rawSeed):
            let seed = (await hydrator.hydrate([rawSeed])).first ?? rawSeed
            guard seed.bpm != nil, seed.camelot != nil else { state = .seedMiss(seed); return }

            let pool = library.readAll().filter {
                ($0.genre?.lowercased()).map(CandidatePipeline.allowlist.contains) ?? false
            }
            let hydrated = await hydrator.hydrate(pool)
            let hydratedCount = hydrated.filter { $0.bpm != nil }.count
            let matches = pipeline.shortlist(seed: seed, candidates: hydrated)

            if hydratedCount < pool.count {
                state = .indexing(seed: seed, shown: matches, total: pool.count, hydrated: hydratedCount)
                return
            }

            let discover = await discover(seed: seed, libraryIds: Set(hydrated.map(\.id)))
            if matches.isEmpty && discover.isEmpty {
                state = .noMatches(seed)
            } else {
                state = .ready(seed: seed, matches: matches, discover: discover)
            }
        }
    }

    /// Widen beyond the library: GetSongBPM tempo/key search → confirm each on Apple Music.
    private func discover(seed: Track, libraryIds: Set<String>) async -> [ScoredCandidate] {
        guard let bpm = seed.bpm, let camelot = seed.camelot else { return [] }
        let client = GetSongBpmClient(apiKey: apiKey)
        let resolver = iTunesResolver()
        let raw = await client.discover(targetBPM: bpm, camelot: camelot)

        var confirmed: [Track] = []
        for t in raw where !libraryIds.contains(t.id) {
            if let match = await resolver.resolve(artist: t.artist, title: t.title) {
                confirmed.append(Track(id: t.id, title: t.title, artist: t.artist, genre: nil,
                                       bpm: t.bpm, camelot: t.camelot, appleMusicURL: match.appleMusicURL))
            }
        }
        return pipeline.shortlistDiscover(seed: seed, candidates: confirmed)
    }

    private static func defaultCachePath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Autocrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("features.sqlite").path
    }
}
