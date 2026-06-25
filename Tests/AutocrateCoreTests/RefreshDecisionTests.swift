// Tests/AutocrateCoreTests/RefreshDecisionTests.swift
import XCTest
@testable import AutocrateCore

final class RefreshDecisionTests: XCTestCase {
    func testSameTrackSkips() {
        XCTAssertEqual(RefreshDecision.evaluate(currentSeedID: "a|x", newSeedID: "a|x"), .skip)
    }

    func testDifferentTrackRefreshes() {
        XCTAssertEqual(RefreshDecision.evaluate(currentSeedID: "a|x", newSeedID: "b|y"), .refresh)
    }

    func testNowStoppedRefreshes() {
        // was showing a track, now nothing playing → refresh to render the stopped state
        XCTAssertEqual(RefreshDecision.evaluate(currentSeedID: "a|x", newSeedID: nil), .refresh)
    }

    func testNoCurrentSeedRefreshes() {
        // panel was loading/nothingPlaying (no seed on screen), something is playing → refresh
        XCTAssertEqual(RefreshDecision.evaluate(currentSeedID: nil, newSeedID: "a|x"), .refresh)
    }

    func testBothNilRefreshes() {
        XCTAssertEqual(RefreshDecision.evaluate(currentSeedID: nil, newSeedID: nil), .refresh)
    }
}
