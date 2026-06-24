import XCTest
@testable import AutocrateCore

final class CandidatePipelineTests: XCTestCase {
    private let pipeline = CandidatePipeline()
    private func seed() -> Track {
        Track(id: "seed", title: "seed", artist: "s", genre: "House", bpm: 128, camelot: CamelotKey("8A"))
    }
    private func cand(_ id: String, genre: String?, bpm: Double?, camelot: String?) -> Track {
        Track(id: id, title: id, artist: "a", genre: genre,
              bpm: bpm, camelot: camelot.flatMap(CamelotKey.init))
    }

    func test_excludesNonAllowlistGenre() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("country", genre: "Country", bpm: 128, camelot: "8A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesOutOfBandBpm() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("skrillex", genre: "Dubstep", bpm: 140, camelot: "8A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesIncompatibleCamelot() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("clash", genre: "House", bpm: 128, camelot: "10A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesMissingKey() {
        // Key is the product — no Camelot means no harmonic relation, so drop it.
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("noKey", genre: "House", bpm: 128, camelot: nil)
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_keepsKeyOnlyCandidateWhenBpmMissing() {
        // BPM is a soft factor under DSP: a compatible key with no BPM is still a valid pick.
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("keyOnly", genre: "House", bpm: nil, camelot: "8A")
        ])
        XCTAssertEqual(out.map(\.track.id), ["keyOnly"])
        XCTAssertNil(out.first?.bpm)
    }
    func test_keyOnlyRanksBelowInBandMatchAtSameRelation() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("keyOnly", genre: "House", bpm: nil, camelot: "8A"),
            cand("inBand",  genre: "House", bpm: 128, camelot: "8A")
        ])
        XCTAssertEqual(out.map(\.track.id), ["inBand", "keyOnly"])
    }
    func test_keepsAndRanksCompatible() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("adjacent", genre: "House", bpm: 128, camelot: "9A"),
            cand("perfect",  genre: "Trance", bpm: 128, camelot: "8A")
        ])
        XCTAssertEqual(out.map(\.track.id), ["perfect", "adjacent"])
    }
    func test_excludesSeedItself() {
        let s = seed()
        let out = pipeline.shortlist(seed: s, candidates: [s])
        XCTAssertTrue(out.isEmpty)
    }
}
