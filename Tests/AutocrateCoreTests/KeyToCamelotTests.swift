import XCTest
@testable import AutocrateCore

final class KeyToCamelotTests: XCTestCase {
    private func c(_ s: String) -> String? { KeyToCamelot.camelot(forMusicalKey: s)?.description }

    func test_canonicalMinors() {
        XCTAssertEqual(c("A minor"), "8A")
        XCTAssertEqual(c("E minor"), "9A")
        XCTAssertEqual(c("D minor"), "7A")
    }
    func test_canonicalMajors() {
        XCTAssertEqual(c("C major"), "8B")
        XCTAssertEqual(c("G major"), "9B")
        XCTAssertEqual(c("F major"), "7B")
    }
    func test_sharpsAndFlatsEnharmonic() {
        XCTAssertEqual(c("F# minor"), "11A")
        XCTAssertEqual(c("Gb minor"), "11A")   // enharmonic of F#
        XCTAssertEqual(c("Db major"), "3B")
        XCTAssertEqual(c("C# major"), "3B")    // enharmonic of Db
        XCTAssertEqual(c("Ab minor"), "1A")
        XCTAssertEqual(c("G# minor"), "1A")
    }
    func test_caseAndWhitespaceTolerant() {
        XCTAssertEqual(c("  a   MINOR "), "8A")
        XCTAssertEqual(c("amin"), "8A")
        XCTAssertEqual(c("Cmaj"), "8B")
    }
    func test_unparseableReturnsNil() {
        XCTAssertNil(c("H minor"))
        XCTAssertNil(c(""))
        XCTAssertNil(c("A"))           // no mode
    }
    func test_allTwentyFourAreCovered() {
        let keys = ["C","G","D","A","E","B","F#","Db","Ab","Eb","Bb","F"]
        for k in keys {
            XCTAssertNotNil(c("\(k) major"), "\(k) major")
            XCTAssertNotNil(c("\(k) minor"), "\(k) minor")
        }
    }
}
