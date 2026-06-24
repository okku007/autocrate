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

    private func apply(_ f: CachedFeature, to track: Track) -> Track {
        Track(id: track.id, title: track.title, artist: track.artist, genre: track.genre,
              bpm: f.state == .found ? f.bpm : nil,
              camelot: f.camelot.flatMap(CamelotKey.init))
    }
}
