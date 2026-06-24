import XCTest
@testable import AutocrateCore

final class BpmBandTests: XCTestCase {
    func test_exactMatch_closenessOne_notShifted() {
        let m = BpmBand.evaluate(seedBPM: 128, candidateBPM: 128)
        XCTAssertEqual(m?.closeness ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(m?.tempoShifted, false)
    }
    func test_withinBand_upperEdge() {
        // 128 * 1.06 = 135.68
        XCTAssertNotNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 135.6))
    }
    func test_withinBand_lowerEdge() {
        // 128 * 0.94 = 120.32
        XCTAssertNotNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 120.4))
    }
    func test_outOfBand_returnsNil() {
        XCTAssertNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 140)) // Skrillex problem
        XCTAssertNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 110))
    }
    func test_halfTime_passesFlaggedShifted() {
        // 64 * 2 = 128 -> in band
        let m = BpmBand.evaluate(seedBPM: 128, candidateBPM: 64)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.tempoShifted, true)
    }
    func test_doubleTime_passesFlaggedShifted() {
        // 256 / 2 = 128 -> in band
        let m = BpmBand.evaluate(seedBPM: 128, candidateBPM: 256)
        XCTAssertEqual(m?.tempoShifted, true)
    }
    func test_closenessDecreasesWithDistance() {
        let near = BpmBand.evaluate(seedBPM: 128, candidateBPM: 129)!.closeness
        let far  = BpmBand.evaluate(seedBPM: 128, candidateBPM: 134)!.closeness
        XCTAssertGreaterThan(near, far)
    }
}
