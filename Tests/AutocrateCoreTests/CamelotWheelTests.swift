import XCTest
@testable import AutocrateCore

final class CamelotWheelTests: XCTestCase {
    private func rel(_ a: String, _ b: String) -> CamelotRelation? {
        CamelotWheel.relation(seed: CamelotKey(a)!, candidate: CamelotKey(b)!)
    }
    func test_perfect_sameKey() {
        XCTAssertEqual(rel("8A", "8A"), .perfect)
    }
    func test_relative_sameNumberOppositeLetter() {
        XCTAssertEqual(rel("8A", "8B"), .relative)
    }
    func test_adjacent_plusOne() {
        XCTAssertEqual(rel("8A", "9A"), .adjacent)
    }
    func test_adjacent_minusOne() {
        XCTAssertEqual(rel("8A", "7A"), .adjacent)
    }
    func test_adjacent_wrap_12_to_1() {
        XCTAssertEqual(rel("12A", "1A"), .adjacent)
        XCTAssertEqual(rel("1A", "12A"), .adjacent)
    }
    func test_incompatible_returnsNil() {
        XCTAssertNil(rel("8A", "10A"))   // two steps away
        XCTAssertNil(rel("8A", "9B"))    // diagonal excluded in v1
        XCTAssertNil(rel("8A", "10B"))
    }
    func test_weightOrdering() {
        XCTAssertGreaterThan(CamelotRelation.perfect.weight, CamelotRelation.relative.weight)
        XCTAssertGreaterThan(CamelotRelation.relative.weight, CamelotRelation.adjacent.weight)
    }
}
