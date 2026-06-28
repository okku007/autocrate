import XCTest
@testable import AutocrateCore

final class FeatureCacheCoverageTests: XCTestCase {
    func testCoverageCountsCamelotAndBpm() throws {
        let cache = try FeatureCache(path: ":memory:")
        let now = 0
        try cache.upsert(CachedFeature(id: "1", title: "a", artist: "x", bpm: 128, camelot: "8A",
                                       musicalKey: nil, source: "dsp", state: .found, fetchedAt: now))
        try cache.upsert(CachedFeature(id: "2", title: "b", artist: "x", bpm: nil, camelot: "5A",
                                       musicalKey: nil, source: "dsp", state: .found, fetchedAt: now))
        try cache.upsert(CachedFeature(id: "3", title: "c", artist: "x", bpm: nil, camelot: nil,
                                       musicalKey: nil, source: "dsp", state: .miss, fetchedAt: now))
        XCTAssertEqual(try cache.coverage(), FeatureCache.Coverage(rows: 3, withCamelot: 2, withBpm: 1))
    }
}
