import XCTest
@testable import AutocrateCore

private struct StubProvider: FeatureProvider {
    let foundIDs: Set<String>
    func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        let found = foundIDs.contains(id)
        return CachedFeature(id: id, title: title, artist: artist,
                             bpm: found ? 128 : nil, camelot: found ? "8A" : nil,
                             musicalKey: nil, source: "dsp", state: found ? .found : .miss, fetchedAt: 0)
    }
}

final class WarmAllProgressTests: XCTestCase {
    func testProgressTalliesFoundAndMissed() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let hydrator = FeatureHydrator(cache: cache,
                                       provider: StubProvider(foundIDs: ["1", "2"]),
                                       acceptsCached: { ["dsp", "dsp+api"].contains($0.source) })
        let tracks = (1...4).map { Track(id: "\($0)", title: "t\($0)", artist: "a",
                                         genre: nil, bpm: nil, camelot: nil) }
        let box = TallyBox()
        await hydrator.warmAll(tracks, concurrency: 2) { box.set($0) }
        XCTAssertEqual(box.last, ScanTally(scanned: 4, total: 4, found: 2, missed: 2))
    }

    func testResumeSkipsCachedRows() async throws {
        let cache = try FeatureCache(path: ":memory:")
        try cache.upsert(CachedFeature(id: "1", title: "t1", artist: "a", bpm: 128, camelot: "8A",
                                       musicalKey: nil, source: "dsp", state: .found, fetchedAt: 0))
        let hydrator = FeatureHydrator(cache: cache,
                                       provider: StubProvider(foundIDs: ["1", "2"]),
                                       acceptsCached: { HybridFeatureProvider.dspSources.contains($0.source) })
        let tracks = (1...4).map { Track(id: "\($0)", title: "t\($0)", artist: "a",
                                         genre: nil, bpm: nil, camelot: nil) }
        let box = TallyBox()
        await hydrator.warmAll(tracks, concurrency: 2) { box.set($0) }
        // "1" already cached → skippedCached (scanned only). "2" found; "3"/"4" miss.
        XCTAssertEqual(box.last, ScanTally(scanned: 4, total: 4, found: 1, missed: 2))
    }
}

private final class TallyBox: @unchecked Sendable {
    private let lock = NSLock(); private var value: ScanTally?
    func set(_ t: ScanTally) { lock.lock(); value = t; lock.unlock() }
    var last: ScanTally? { lock.lock(); defer { lock.unlock() }; return value }
}
