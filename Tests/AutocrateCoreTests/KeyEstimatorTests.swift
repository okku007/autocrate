import XCTest
@testable import AutocrateCore

final class KeyEstimatorTests: XCTestCase {
    // Krumhansl–Schmuckler key profiles (tonic-relative, index 0 = tonic).
    static let ksMaj: [Float] = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88]
    static let ksMin: [Float] = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17]
    /// A chroma vector for the key whose tonic sits at pitch class `tonic`.
    private func rolled(_ p: [Float], by tonic: Int) -> [Float] { (0..<12).map { p[(($0 - tonic) % 12 + 12) % 12] } }

    func test_cMajorProfileMapsTo8B() {
        XCTAssertEqual(KeyEstimator.keyFromChroma(Self.ksMaj).camelot, CamelotKey("8B"))
    }
    func test_gMajorProfileMapsTo9B() {
        XCTAssertEqual(KeyEstimator.keyFromChroma(rolled(Self.ksMaj, by: 7)).camelot, CamelotKey("9B"))
    }
    func test_cMinorProfileMapsTo5A() {
        XCTAssertEqual(KeyEstimator.keyFromChroma(Self.ksMin).camelot, CamelotKey("5A"))
    }
    func test_pureA440ChromaPeaksAtPitchClassA() {
        let sr = 22050.0
        let tone = (0..<Int(sr)).map { Float(sin(2 * Double.pi * 440 * Double($0) / sr)) }
        let ch = KeyEstimator.chroma(tone, sampleRate: sr)
        XCTAssertEqual(ch.firstIndex(of: ch.max()!), 9)   // pitch class A
    }
}
