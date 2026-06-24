import XCTest
@testable import AutocrateCore

final class RankerTests: XCTestCase {
    private func cand(_ id: String, _ rel: CamelotRelation, closeness: Double?, shifted: Bool = false) -> ScoredCandidate {
        ScoredCandidate(
            track: Track(id: id, title: id, artist: "x", genre: "House", bpm: 128, camelot: CamelotKey("8A")),
            relation: rel,
            bpm: closeness.map { BpmMatch(closeness: $0, tempoShifted: shifted) },
            score: 0
        )
    }
    func test_perfectOutranksRelativeOutranksAdjacent() {
        let ranked = Ranker.rank([
            cand("adj", .adjacent, closeness: 1),
            cand("perf", .perfect, closeness: 0.1),
            cand("rel", .relative, closeness: 1)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["perf", "rel", "adj"])
    }
    func test_tieBrokenByBpmCloseness() {
        let ranked = Ranker.rank([
            cand("far", .perfect, closeness: 0.2),
            cand("near", .perfect, closeness: 0.9)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["near", "far"])
    }
    func test_exactRanksAboveTempoShifted_whenOtherwiseEqual() {
        let ranked = Ranker.rank([
            cand("shifted", .perfect, closeness: 0.5, shifted: true),
            cand("exact", .perfect, closeness: 0.5, shifted: false)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["exact", "shifted"])
    }
    func test_scoreIsPopulated() {
        let ranked = Ranker.rank([cand("a", .perfect, closeness: 1)])
        XCTAssertGreaterThan(ranked[0].score, 0)
    }
    func test_nilBpmScoresRelationWeightOnly() {
        let ranked = Ranker.rank([cand("keyOnly", .perfect, closeness: nil)])
        XCTAssertEqual(ranked[0].score, Double(CamelotRelation.perfect.weight))  // weight + 0
    }
    func test_matchedBpmRanksAboveNilAtSameRelation() {
        let ranked = Ranker.rank([
            cand("keyOnly", .perfect, closeness: nil),
            cand("matched", .perfect, closeness: 0.3)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["matched", "keyOnly"])
    }
    func test_higherRelationBeatsNilBpmRegardless() {
        // nil BPM is not penalized below a lower-relation candidate.
        let ranked = Ranker.rank([
            cand("adjMatched", .adjacent, closeness: 1),
            cand("perfKeyOnly", .perfect, closeness: nil)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["perfKeyOnly", "adjMatched"])
    }
}
