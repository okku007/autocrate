import XCTest
@testable import AutocrateCore

final class LibraryWindowCacheTests: XCTestCase {
    private func row(_ id: String, camelot: String?, bpm: Double?) -> CachedFeature {
        CachedFeature(id: id, title: id, artist: "a", bpm: bpm, camelot: camelot,
                      musicalKey: nil, source: "dsp", state: .found, fetchedAt: 0)
    }

    func test_analyzedFeaturesReturnsOnlyRowsWithCamelot() throws {
        let cache = try FeatureCache(path: ":memory:")
        try cache.upsert(row("a", camelot: "8A", bpm: 128))
        try cache.upsert(row("b", camelot: nil, bpm: nil))   // miss row: analyzed but no key
        XCTAssertEqual(try cache.analyzedFeatures().map(\.id).sorted(), ["a"])
    }

    func test_missedIDsReturnsRowsWithoutCamelot() throws {
        let cache = try FeatureCache(path: ":memory:")
        try cache.upsert(row("a", camelot: "8A", bpm: 128))
        try cache.upsert(row("b", camelot: nil, bpm: nil))
        XCTAssertEqual(try cache.missedIDs().sorted(), ["b"])
    }

    func test_trackFromFeatureParsesCamelotAndDropsGenre() {
        let track = Track(feature: row("x", camelot: "9B", bpm: 124))
        XCTAssertEqual(track.camelot, CamelotKey("9B"))
        XCTAssertEqual(track.bpm, 124)
        XCTAssertNil(track.genre)
        XCTAssertEqual(track.id, "x")
    }
}
