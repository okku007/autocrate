import XCTest
@testable import AutocrateCore

final class RateLimiterTests: XCTestCase {
    func test_firstAcquireIsImmediate() async {
        let limiter = RateLimiter(minInterval: .seconds(10))
        let clock = ContinuousClock()
        let start = clock.now
        await limiter.acquire()
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(500))
    }
    func test_spacesConsecutiveAcquisitionsByMinInterval() async {
        let limiter = RateLimiter(minInterval: .milliseconds(120))
        let clock = ContinuousClock()
        let start = clock.now
        await limiter.acquire()   // immediate
        await limiter.acquire()   // must wait ~120ms
        XCTAssertGreaterThanOrEqual(start.duration(to: clock.now), .milliseconds(100))
    }
    func test_concurrentAcquisitionsAreSerializedNotCoalesced() async {
        // Three callers at once must still come out ~minInterval apart, not all at once.
        let limiter = RateLimiter(minInterval: .milliseconds(80))
        let clock = ContinuousClock()
        let start = clock.now
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<3 { g.addTask { await limiter.acquire() } }
        }
        // 3 slots spaced 80ms → last finishes ≥ ~160ms after start.
        XCTAssertGreaterThanOrEqual(start.duration(to: clock.now), .milliseconds(140))
    }
}
