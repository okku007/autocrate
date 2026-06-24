import XCTest
@testable import AutocrateCore

final class FeatureCacheTests: XCTestCase {
    private func makeCache() throws -> FeatureCache { try FeatureCache(path: ":memory:") }

    private func feature(_ id: String, state: LookupState = .found) -> CachedFeature {
        CachedFeature(id: id, title: "T", artist: "A", bpm: 128, camelot: "8A",
                      musicalKey: "A minor", source: "getsongbpm", state: state, fetchedAt: 1)
    }

    func test_upsertThenFetchRoundTrips() throws {
        let cache = try makeCache()
        try cache.upsert(feature("a|b"))
        XCTAssertEqual(try cache.fetch(id: "a|b"), feature("a|b"))
    }
    func test_fetchMissingReturnsNil() throws {
        let cache = try makeCache()
        XCTAssertNil(try cache.fetch(id: "nope"))
    }
    func test_missStateIsPersisted() throws {
        let cache = try makeCache()
        let miss = CachedFeature(id: "x", title: "T", artist: "A", bpm: nil, camelot: nil,
                                 musicalKey: nil, source: "getsongbpm", state: .miss, fetchedAt: 2)
        try cache.upsert(miss)
        XCTAssertEqual(try cache.fetch(id: "x")?.state, .miss)
    }
    func test_upsertReplacesExisting() throws {
        let cache = try makeCache()
        try cache.upsert(feature("a|b", state: .miss))
        try cache.upsert(feature("a|b", state: .found))
        XCTAssertEqual(try cache.fetch(id: "a|b")?.state, .found)
    }
}
