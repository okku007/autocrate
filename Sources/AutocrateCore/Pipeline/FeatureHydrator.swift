import Foundation

/// Lazily fills track features from the cache, fetching misses via the provider.
/// Capped per call and throttled, so a cold cache never hammers the API.
public actor FeatureHydrator {
    private let cache: FeatureCache
    private let provider: FeatureProvider
    private let cap: Int
    private let throttle: Duration

    public init(cache: FeatureCache, provider: FeatureProvider, cap: Int = 50, throttle: Duration = .seconds(1)) {
        self.cache = cache
        self.provider = provider
        self.cap = cap
        self.throttle = throttle
    }

    /// Returns the tracks with bpm/camelot populated where known. Uncached tracks beyond
    /// the per-call cap, and misses, come back with nil features.
    public func hydrate(_ tracks: [Track]) async -> [Track] {
        var fetched = 0
        var result: [Track] = []
        for track in tracks {
            if let cached = try? cache.fetch(id: track.id) {
                result.append(apply(cached, to: track))
                continue
            }
            guard fetched < cap else { result.append(track); continue }
            if fetched > 0, throttle > .zero { try? await Task.sleep(for: throttle) }
            let feature = await provider.lookup(artist: track.artist, title: track.title, id: track.id)
            try? cache.upsert(feature)
            fetched += 1
            result.append(apply(feature, to: track))
        }
        return result
    }

    /// Like `hydrate`, but yields the cumulative result as it goes so callers can render progress.
    /// Same cache/cap/throttle semantics. Yields on every network step (which are throttle-spaced
    /// anyway), periodically through the fast cached pass, and once more at the end.
    public nonisolated func hydrateProgressively(_ tracks: [Track]) -> AsyncStream<(scanned: Int, tracks: [Track])> {
        AsyncStream { continuation in
            let task = Task { await self.streamHydrate(tracks, into: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamHydrate(_ tracks: [Track],
                               into continuation: AsyncStream<(scanned: Int, tracks: [Track])>.Continuation) async {
        var fetched = 0
        var result: [Track] = []
        for (i, track) in tracks.enumerated() {
            if Task.isCancelled { break }
            var didNetwork = false
            if let cached = try? cache.fetch(id: track.id) {
                result.append(apply(cached, to: track))
            } else if fetched < cap {
                if fetched > 0, throttle > .zero { try? await Task.sleep(for: throttle) }
                let feature = await provider.lookup(artist: track.artist, title: track.title, id: track.id)
                try? cache.upsert(feature)
                fetched += 1
                result.append(apply(feature, to: track))
                didNetwork = true
            } else {
                result.append(track)
            }
            let scanned = i + 1
            if didNetwork || scanned % 50 == 0 || scanned == tracks.count {
                continuation.yield((scanned, result))
            }
        }
        continuation.finish()
    }

    private func apply(_ f: CachedFeature, to track: Track) -> Track {
        Track(id: track.id, title: track.title, artist: track.artist, genre: track.genre,
              bpm: f.state == .found ? f.bpm : nil,
              camelot: f.camelot.flatMap(CamelotKey.init))
    }
}
