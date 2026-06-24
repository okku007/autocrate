import Foundation
import AutocrateCore

/// Every state the panel can render.
public enum PanelState: Equatable {
    case loading
    case nothingPlaying
    case permissionDenied
    /// Seed is known and on screen; still resolving its BPM/key and scanning the library.
    case preparing(seed: Track)
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
        // Hybrid, key-dominant: Camelot always from on-device DSP of Apple's preview clips
        // (full coverage); BPM backfilled from GetSongBPM when DSP isn't confident. DSP is local +
        // we don't self-throttle Apple's endpoints, so throttle .zero and a high cap.
        self.hydrator = FeatureHydrator(
            cache: cache,
            provider: HybridFeatureProvider(
                dsp: PreviewDSPProvider(),
                bpmFallback: GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey)
            ),
            cap: 100,
            throttle: .zero,
            acceptsCached: HybridFeatureProvider.acceptsCached   // re-fetch stale legacy rows
        )
    }

    private var didPrewarm = false

    /// Warms the feature cache for the whole compatible library in the background so later panel
    /// opens hit a warm cache and render instantly. Idempotent — safe to call on every panel open.
    public func prewarm() {
        guard !didPrewarm else { return }
        didPrewarm = true
        let hydrator = self.hydrator
        let library = self.library
        Task.detached(priority: .utility) {
            let pool = (await library.readAllAsync()).filter {
                ($0.genre?.lowercased()).map(CandidatePipeline.allowlist.contains) ?? false
            }
            await hydrator.warmAll(pool)
        }
    }

    public func refresh() async {
        state = .loading
        switch nowPlaying.read() {
        case .permissionDenied:
            state = .permissionDenied
        case .stopped:
            state = .nothingPlaying
        case .playing(let rawSeed):
            // Show the song the instant we read it, before any (possibly slow) lookups.
            state = .preparing(seed: rawSeed)

            let seed = (await hydrator.hydrate([rawSeed])).first ?? rawSeed
            guard seed.bpm != nil, seed.camelot != nil else { state = .seedMiss(seed); return }
            state = .preparing(seed: seed)   // header now carries the seed's BPM/key

            let pool = (await library.readAllAsync()).filter {
                ($0.genre?.lowercased()).map(CandidatePipeline.allowlist.contains) ?? false
            }
            guard !pool.isEmpty else { state = .noMatches(seed); return }
            state = .indexing(seed: seed, shown: [], total: pool.count, hydrated: 0)

            // Stream hydration: surface matches and a climbing scan count as the library warms.
            var hydrated: [Track] = []
            for await (scanned, tracks) in hydrator.hydrateProgressively(pool) {
                hydrated = tracks
                let matches = pipeline.shortlist(seed: seed, candidates: tracks)
                state = .indexing(seed: seed, shown: matches, total: pool.count, hydrated: scanned)
            }

            let matches = pipeline.shortlist(seed: seed, candidates: hydrated)
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
