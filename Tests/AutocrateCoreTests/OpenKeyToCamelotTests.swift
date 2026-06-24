import XCTest
@testable import AutocrateCore

final class OpenKeyToCamelotTests: XCTestCase {
    private func c(_ s: String) -> String? { KeyToCamelot.camelot(forOpenKey: s)?.description }

    func test_minorMapsToLetterA() {
        XCTAssertEqual(c("6m"), "1A")   // G♯ minor (deadmau5 – Strobe)
        XCTAssertEqual(c("8m"), "3A")
    }
    func test_majorMapsToLetterB() {
        XCTAssertEqual(c("9d"), "4B")   // G♯ major (Zedd – Clarity)
        XCTAssertEqual(c("3d"), "10B")  // D major (Daft Punk – One More Time)
    }
    func test_wrapsAroundTwelve() {
        XCTAssertEqual(c("7d"), "2B")   // ((7+6)%12)+1 = 2
        XCTAssertEqual(c("12m"), "7A")
        XCTAssertEqual(c("1m"), "8A")
    }
    func test_caseInsensitive() {
        XCTAssertEqual(c("6M"), "1A")
        XCTAssertEqual(c("9D"), "4B")
    }
    func test_invalidReturnsNil() {
        XCTAssertNil(c(""))
        XCTAssertNil(c("13m"))   // out of range
        XCTAssertNil(c("0d"))
        XCTAssertNil(c("6x"))    // bad letter
        XCTAssertNil(c("abc"))
        XCTAssertNil(c("m"))
    }
}
