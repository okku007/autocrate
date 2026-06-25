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

    /// Retained so closing the panel mid-scan does not cancel hydration (the poll loop is the
    /// view's; this Task is the engine's). Superseded — cancelled and replaced — when the track
    /// changes. nil ⇔ idle.
    private var refreshTask: Task<Void, Never>?
    private let manualCooldown = Cooldown(interval: 60)
    /// Lives on the persisted engine so reopening the panel can't reset the manual-refresh limit.
    private var lastManualRefresh: Date?

    public init() {
        let cache = try! FeatureCache(path: Self.defaultCachePath())
        self.cache = cache
        self.apiKey = Secrets.getSongBpmApiKey
        // Hybrid, key-dominant: Camelot always from on-device DSP of Apple's preview clips;
        // BPM backfilled from GetSongBPM when DSP isn't confident. iTunes Search (used to resolve
        // each preview URL) rate-limits ~20/min and IP-bans bulk access, so there is NO background
        // pre-warm — each panel open resolves only a bounded batch (`cap`), paced by the resolver's
        // shared limiter. Coverage builds gradually across normal use; the cache persists forever.
        self.hydrator = FeatureHydrator(
            cache: cache,
            provider: HybridFeatureProvider(
                dsp: PreviewDSPProvider(),
                bpmFallback: GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey)
            ),
            cap: 30,
            throttle: .zero,                                     // iTunes pacing is handled by the resolver's RateLimiter
            acceptsCached: HybridFeatureProvider.acceptsCached   // re-fetch stale legacy rows
        )
    }

    /// Polled while the panel is open (and called on open). Re-queries only when the now-playing
    /// track differs from what's on screen — same track is a no-op, so polling is cheap (one local
    /// now-playing read). A genuine track change supersedes any in-flight refresh for the old track.
    public func refreshIfNeeded() {
        let newSeedID: String?
        if case .playing(let t) = nowPlaying.read() { newSeedID = t.id } else { newSeedID = nil }
        switch RefreshDecision.evaluate(currentSeedID: currentSeedID, newSeedID: newSeedID) {
        case .skip: return
        case .refresh: startRefresh()
        }
    }

    /// The manual refresh button. Bypasses the track-change gate; still bounded by the 60s cooldown
    /// and by any in-flight refresh.
    public func forceRefresh() {
        guard refreshTask == nil else { return }
        guard manualCooldown.allows(now: Date(), last: lastManualRefresh) else { return }
        lastManualRefresh = Date()
        startRefresh()
    }

    /// Drives the refresh button's enabled state.
    public var canManualRefresh: Bool {
        refreshTask == nil && manualCooldown.allows(now: Date(), last: lastManualRefresh)
    }

    /// id of the seed currently on screen, or nil when no seed is shown.
    private var currentSeedID: String? {
        switch state {
        case .preparing(let s), .seedMiss(let s), .noMatches(let s): return s.id
        case .indexing(let s, _, _, _): return s.id
        case .ready(let s, _, _): return s.id
        case .loading, .nothingPlaying, .permissionDenied: return nil
        }
    }

    private func startRefresh() {
        refreshTask?.cancel()                 // supersede any in-flight refresh for the old track
        refreshTask = Task { [weak self] in
            await self?.refresh()
            // Only the live (non-superseded) task clears the handle; a cancelled one must not
            // null out its replacement.
            guard let self, !Task.isCancelled else { return }
            self.refreshTask = nil
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
            // Cancelled ⇒ the track changed under us; bail before touching state so a stale
            // refresh can't clobber the one now running for the new track.
            if Task.isCancelled { return }
            guard seed.bpm != nil, seed.camelot != nil else { state = .seedMiss(seed); return }
            state = .preparing(seed: seed)   // header now carries the seed's BPM/key

            let pool = (await library.readAllAsync()).filter {
                ($0.genre?.lowercased()).map(CandidatePipeline.allowlist.contains) ?? false
            }
            if Task.isCancelled { return }
            guard !pool.isEmpty else { state = .noMatches(seed); return }
            state = .indexing(seed: seed, shown: [], total: pool.count, hydrated: 0)

            // Stream hydration: surface matches and a climbing scan count as the library warms.
            var hydrated: [Track] = []
            for await (scanned, tracks) in hydrator.hydrateProgressively(pool) {
                if Task.isCancelled { return }   // stop the stale scan the instant the track changes
                hydrated = tracks
                let matches = pipeline.shortlist(seed: seed, candidates: tracks)
                state = .indexing(seed: seed, shown: matches, total: pool.count, hydrated: scanned)
            }

            if Task.isCancelled { return }
            let matches = pipeline.shortlist(seed: seed, candidates: hydrated)
            let discover = await discover(seed: seed, libraryIds: Set(hydrated.map(\.id)))
            if Task.isCancelled { return }
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
            if Task.isCancelled { break }   // track changed — don't burn rate-limited iTunes calls
            if let match = try? await resolver.resolve(artist: t.artist, title: t.title) {
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
