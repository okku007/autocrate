import XCTest
@testable import AutocrateCore

private final class FakeProvider: FeatureProvider {
    var calls = 0
    let bpmByTitle: [String: Double]
    init(_ bpmByTitle: [String: Double]) { self.bpmByTitle = bpmByTitle }
    func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        calls += 1
        if let bpm = bpmByTitle[title] {
            return CachedFeature(id: id, title: title, artist: artist, bpm: bpm, camelot: "8A",
                                 musicalKey: "A minor", source: "fake", state: .found, fetchedAt: 0)
        }
        return CachedFeature(id: id, title: title, artist: artist, bpm: nil, camelot: nil,
                             musicalKey: nil, source: "fake", state: .miss, fetchedAt: 0)
    }
}

final class FeatureHydratorTests: XCTestCase {
    private func track(_ t: String) -> Track {
        Track(id: "a|\(t)", title: t, artist: "a", genre: "House", bpm: nil, camelot: nil)
    }

    func test_fillsFeaturesFromProviderAndPersists() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["x": 128])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        let out = await hydrator.hydrate([track("x")])
        XCTAssertEqual(out.first?.bpm, 128)
        XCTAssertEqual(out.first?.camelot, CamelotKey("8A"))
        XCTAssertEqual(try cache.fetch(id: "a|x")?.state, .found)
    }
    func test_secondCallHitsCacheNotProvider() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["x": 128])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        _ = await hydrator.hydrate([track("x")])
        _ = await hydrator.hydrate([track("x")])
        XCTAssertEqual(provider.calls, 1)   // second call served from cache
    }
    func test_respectsPerSessionCap() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["a": 128, "b": 128, "c": 128])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 2, throttle: .zero)
        _ = await hydrator.hydrate([track("a"), track("b"), track("c")])
        XCTAssertEqual(provider.calls, 2)   // capped
    }
    func test_missComesBackWithNilFeatures() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider([:])     // everything misses
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        let out = await hydrator.hydrate([track("x")])
        XCTAssertNil(out.first?.bpm)
    }
    func test_progressiveStreamYieldsMonotonicScanAndFullFinalResult() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["a": 120, "b": 130])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        var lastScanned = 0
        var finalTracks: [Track] = []
        for await (scanned, tracks) in hydrator.hydrateProgressively([track("a"), track("b")]) {
            XCTAssertGreaterThanOrEqual(scanned, lastScanned)   // scan count never goes backwards
            lastScanned = scanned
            finalTracks = tracks
        }
        XCTAssertEqual(lastScanned, 2)
        XCTAssertEqual(finalTracks.map(\.bpm), [120, 130])      // cumulative, fully hydrated at the end
    }
}
