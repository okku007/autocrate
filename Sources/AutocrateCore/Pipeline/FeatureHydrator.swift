import Foundation

/// Running counts emitted by `FeatureHydrator.warmAll` for progress display.
public struct ScanTally: Sendable, Equatable {
    public let scanned, total, found, missed: Int
    public init(scanned: Int, total: Int, found: Int, missed: Int) {
        self.scanned = scanned; self.total = total; self.found = found; self.missed = missed
    }
}

private enum WarmOutcome { case found, missed, skippedCached }

/// Lazily fills track features from the cache, fetching misses via the provider.
/// Capped per call and throttled, so a cold cache never hammers the API.
public actor FeatureHydrator {
    private let cache: FeatureCache
    private let provider: FeatureProvider
    private let cap: Int
    private let throttle: Duration
    /// Whether a cached row may be served as-is. Rows it rejects (e.g. stale legacy sources) are
    /// re-fetched through the provider. Default trusts every cached row.
    private let acceptsCached: @Sendable (CachedFeature) -> Bool

    public init(cache: FeatureCache, provider: FeatureProvider, cap: Int = 50,
                throttle: Duration = .seconds(1),
                acceptsCached: @escaping @Sendable (CachedFeature) -> Bool = { _ in true }) {
        self.cache = cache
        self.provider = provider
        self.cap = cap
        self.throttle = throttle
        self.acceptsCached = acceptsCached
    }

    /// Returns the tracks with bpm/camelot populated where known. Uncached tracks beyond
    /// the per-call cap, and misses, come back with nil features.
    public func hydrate(_ tracks: [Track]) async -> [Track] {
        var fetched = 0
        var result: [Track] = []
        for track in tracks {
            if let cached = try? cache.fetch(id: track.id), acceptsCached(cached) {
                result.append(apply(cached, to: track))
                continue
            }
            guard fetched < cap else { result.append(track); continue }
            if fetched > 0, throttle > .zero { try? await Task.sleep(for: throttle) }
            let feature = await provider.lookup(artist: track.artist, title: track.title, id: track.id)
            if feature.state != .unavailable { try? cache.upsert(feature) }   // don't persist transient failures
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
            if let cached = try? cache.fetch(id: track.id), acceptsCached(cached) {
                result.append(apply(cached, to: track))
            } else if fetched < cap {
                if fetched > 0, throttle > .zero { try? await Task.sleep(for: throttle) }
                let feature = await provider.lookup(artist: track.artist, title: track.title, id: track.id)
                if feature.state != .unavailable { try? cache.upsert(feature) }   // don't persist transient failures
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

    /// Pre-warms the cache for the whole library, ignoring `cap`/`throttle` and fetching up to
    /// `concurrency` tracks at once. Cache-first (skips rows `acceptsCached` trusts). Intended to
    /// run in the background after launch so later panel opens hit a warm cache and render instantly.
    /// `onProgress` is called after each track completes with the running tally.
    public func warmAll(_ tracks: [Track], concurrency: Int = 8,
                        onProgress: @Sendable (ScanTally) -> Void = { _ in }) async {
        let total = tracks.count
        var scanned = 0, found = 0, missed = 0
        var iterator = tracks.makeIterator()
        await withTaskGroup(of: WarmOutcome.self) { group in
            func addNext() {
                guard let t = iterator.next() else { return }
                group.addTask { await self.warmOne(t) }
            }
            for _ in 0..<max(1, min(concurrency, total)) { addNext() }
            while let outcome = await group.next() {
                scanned += 1
                switch outcome {
                case .found: found += 1
                case .missed: missed += 1
                case .skippedCached: break
                }
                onProgress(ScanTally(scanned: scanned, total: total, found: found, missed: missed))
                addNext()
            }
        }
    }

    private func warmOne(_ track: Track) async -> WarmOutcome {
        if let cached = try? cache.fetch(id: track.id), acceptsCached(cached) { return .skippedCached }
        let feature = await provider.lookup(artist: track.artist, title: track.title, id: track.id)
        if feature.state != .unavailable { try? cache.upsert(feature) }   // don't persist transient failures
        return feature.state == .found ? .found : .missed
    }

    private func apply(_ f: CachedFeature, to track: Track) -> Track {
        Track(id: track.id, title: track.title, artist: track.artist, genre: track.genre,
              bpm: f.state == .found ? f.bpm : nil,
              camelot: f.camelot.flatMap(CamelotKey.init))
    }
}
