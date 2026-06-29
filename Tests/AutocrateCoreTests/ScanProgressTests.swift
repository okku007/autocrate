import XCTest
@testable import AutocrateCore

final class ScanProgressTests: XCTestCase {
    func testEtaLinearExtrapolation() throws {
        // 10 of 100 in 10s → 1s/item → 90 remaining → 90s
        let eta = try XCTUnwrap(ScanProgress.etaSeconds(scanned: 10, total: 100, elapsed: 10))
        XCTAssertEqual(eta, 90, accuracy: 0.001)
    }
    func testEtaNilBeforeAnyProgress() {
        XCTAssertNil(ScanProgress.etaSeconds(scanned: 0, total: 100, elapsed: 5))
    }
    func testEtaZeroWhenComplete() throws {
        let eta = try XCTUnwrap(ScanProgress.etaSeconds(scanned: 100, total: 100, elapsed: 50))
        XCTAssertEqual(eta, 0, accuracy: 0.001)
    }
    func testFormatMinutesSeconds() {
        XCTAssertEqual(ScanProgress.format(90), "01:30")
        XCTAssertEqual(ScanProgress.format(nil), "--:--")
    }
    func testFormatHandlesNegativeAndNonFinite() {
        XCTAssertEqual(ScanProgress.format(-1), "--:--")
        XCTAssertEqual(ScanProgress.format(.infinity), "--:--")
        XCTAssertEqual(ScanProgress.format(.nan), "--:--")
    }
}
