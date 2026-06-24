import XCTest
@testable import AutocrateCore

final class TempoEstimatorTests: XCTestCase {
    /// Short impulses every (60/bpm) seconds — an unambiguous beat the estimator must recover.
    private func clickTrack(bpm: Double, seconds: Double, sampleRate: Double) -> [Float] {
        var s = [Float](repeating: 0, count: Int(seconds * sampleRate))
        let period = Int(sampleRate * 60.0 / bpm)
        var i = 0
        while i < s.count {
            for j in 0..<min(64, s.count - i) {            // ~3ms click
                s[i + j] = 1.0 - Float(j) / 64.0
            }
            i += period
        }
        return s
    }

    func test_detectsTempoOfSyntheticClickTrack() {
        let sr = 22050.0
        let samples = clickTrack(bpm: 120, seconds: 8, sampleRate: sr)
        let r = TempoEstimator.estimate(samples, sampleRate: sr, band: 60...180)
        XCTAssertEqual(r.bpm, 120, accuracy: 3)
        XCTAssertGreaterThan(r.confidence, 0.5)
    }

    func test_whiteNoiseHasLowConfidence() {
        let sr = 22050.0
        // Deterministic white noise: no periodic structure → estimator must admit low confidence.
        var seed: UInt64 = 0x1234_5678
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max) }
        let noise = (0..<Int(sr * 5)).map { _ in rnd() }
        let r = TempoEstimator.estimate(noise, sampleRate: sr, band: 60...180)
        XCTAssertLessThan(r.confidence, 0.5)
    }
}
