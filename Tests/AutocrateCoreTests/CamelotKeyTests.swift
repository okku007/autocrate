import XCTest
@testable import AutocrateCore

final class CamelotKeyTests: XCTestCase {
    func test_parsesValidKey() {
        let k = CamelotKey("8A")
        XCTAssertEqual(k?.number, 8)
        XCTAssertEqual(k?.letter, .a)
    }
    func test_parsesTwoDigitNumber() {
        XCTAssertEqual(CamelotKey("12B")?.number, 12)
        XCTAssertEqual(CamelotKey("12B")?.letter, .b)
    }
    func test_isCaseInsensitive() {
        XCTAssertEqual(CamelotKey("8a"), CamelotKey("8A"))
    }
    func test_rejectsOutOfRange() {
        XCTAssertNil(CamelotKey("0A"))
        XCTAssertNil(CamelotKey("13A"))
        XCTAssertNil(CamelotKey("8C"))
        XCTAssertNil(CamelotKey("AA"))
        XCTAssertNil(CamelotKey(""))
    }
    func test_descriptionRoundTrips() {
        XCTAssertEqual(CamelotKey("8A")?.description, "8A")
    }
}
