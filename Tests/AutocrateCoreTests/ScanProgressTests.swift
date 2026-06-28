import XCTest
@testable import AutocrateCore

final class ScanProgressTests: XCTestCase {
    func testEtaLinearExtrapolation() {
        // 10 of 100 in 10s → 1s/item → 90 remaining → 90s
        XCTAssertEqual(ScanProgress.etaSeconds(scanned: 10, total: 100, elapsed: 10)!, 90, accuracy: 0.001)
    }
    func testEtaNilBeforeAnyProgress() {
        XCTAssertNil(ScanProgress.etaSeconds(scanned: 0, total: 100, elapsed: 5))
    }
    func testEtaZeroWhenComplete() {
        XCTAssertEqual(ScanProgress.etaSeconds(scanned: 100, total: 100, elapsed: 50)!, 0, accuracy: 0.001)
    }
    func testFormatMinutesSeconds() {
        XCTAssertEqual(ScanProgress.format(90), "01:30")
        XCTAssertEqual(ScanProgress.format(nil), "--:--")
    }
}
