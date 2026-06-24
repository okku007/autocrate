import XCTest
@testable import AutocrateCore

final class DiscoverPipelineTests: XCTestCase {
    private let pipeline = CandidatePipeline()
    private func seed() -> Track {
        Track(id: "seed", title: "seed", artist: "s", genre: "House", bpm: 128, camelot: CamelotKey("8A"))
    }
    private func cand(_ id: String, bpm: Double?, camelot: String?) -> Track {
        // Discover candidates have no genre tag.
        Track(id: id, title: id, artist: "a", genre: nil, bpm: bpm, camelot: camelot.flatMap(CamelotKey.init))
    }

    func test_keepsCompatibleDespiteNoGenre() {
        let out = pipeline.shortlistDiscover(seed: seed(), candidates: [
            cand("perfect", bpm: 128, camelot: "8A")
        ])
        XCTAssertEqual(out.map(\.track.id), ["perfect"])
    }
    func test_stillGatesOnBpmAndCamelot() {
        let out = pipeline.shortlistDiscover(seed: seed(), candidates: [
            cand("badBpm", bpm: 140, camelot: "8A"),
            cand("badKey", bpm: 128, camelot: "10A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesSeedAndMissingFeatures() {
        let out = pipeline.shortlistDiscover(seed: seed(), candidates: [
            seed(),
            cand("noFeatures", bpm: nil, camelot: nil)
        ])
        XCTAssertTrue(out.isEmpty)
    }
}
