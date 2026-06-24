import XCTest
@testable import AutocrateCore

final class CircuitBreakerTests: XCTestCase {
    func test_startsClosed() async {
        let b = CircuitBreaker(cooldown: .seconds(60))
        let open = await b.isOpen
        XCTAssertFalse(open)
    }
    func test_opensAfterFailure() async {
        let b = CircuitBreaker(cooldown: .seconds(60))
        await b.recordFailure()
        let open = await b.isOpen
        XCTAssertTrue(open)   // a 403/429 trips the breaker → block further calls
    }
    func test_successClosesIt() async {
        let b = CircuitBreaker(cooldown: .seconds(60))
        await b.recordFailure()
        await b.recordSuccess()
        let open = await b.isOpen
        XCTAssertFalse(open)
    }
    func test_reopensToClosedAfterCooldown() async {
        let b = CircuitBreaker(cooldown: .milliseconds(120))
        await b.recordFailure()
        let openNow = await b.isOpen
        XCTAssertTrue(openNow)
        try? await Task.sleep(for: .milliseconds(160))
        let openLater = await b.isOpen   // cooldown elapsed → half-open (allow a retry)
        XCTAssertFalse(openLater)
    }
}
