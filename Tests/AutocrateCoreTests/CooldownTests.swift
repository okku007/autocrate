import XCTest
@testable import AutocrateCore

final class CooldownTests: XCTestCase {
    private let cd = Cooldown(interval: 60)
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testAllowsWhenNoPriorRefresh() {
        XCTAssertTrue(cd.allows(now: t0, last: nil))
    }

    func testBlocksWithinInterval() {
        let last = t0.addingTimeInterval(-30)   // 30s ago, < 60s
        XCTAssertFalse(cd.allows(now: t0, last: last))
    }

    func testAllowsExactlyAtInterval() {
        let last = t0.addingTimeInterval(-60)   // exactly 60s ago
        XCTAssertTrue(cd.allows(now: t0, last: last))
    }

    func testAllowsAfterInterval() {
        let last = t0.addingTimeInterval(-90)
        XCTAssertTrue(cd.allows(now: t0, last: last))
    }

    func testRemainingIsZeroWhenNoPriorRefresh() {
        XCTAssertEqual(cd.remaining(now: t0, last: nil), 0)
    }

    func testRemainingWithinInterval() {
        let last = t0.addingTimeInterval(-20)   // 40s left
        XCTAssertEqual(cd.remaining(now: t0, last: last), 40, accuracy: 0.001)
    }

    func testRemainingIsZeroAfterInterval() {
        let last = t0.addingTimeInterval(-90)
        XCTAssertEqual(cd.remaining(now: t0, last: last), 0)
    }
}
