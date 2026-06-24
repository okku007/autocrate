import XCTest
import AVFoundation
@testable import AutocrateCore

final class AudioDecoderTests: XCTestCase {
    /// Writes a stereo 44.1kHz sine tone to a temp WAV so we can decode it back.
    private func writeTone(_ url: URL, freq: Double, seconds: Double, sampleRate: Double) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<2 {
            let p = buf.floatChannelData![ch]
            for i in 0..<Int(frames) { p[i] = Float(sin(2 * Double.pi * freq * Double(i) / sampleRate)) }
        }
        try file.write(from: buf)
    }

    func test_decodesToMonoAtTargetSampleRate() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsp_\(UUID()).wav")
        try writeTone(url, freq: 440, seconds: 1, sampleRate: 44100)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try await AudioDecoder.monoSamples(url: url, sampleRate: 22050)

        XCTAssertEqual(Double(samples.count), 22050, accuracy: 2205)   // ~1s at 22050, ±10%
        // Survives decode+downmix+resample: a 440Hz tone still reads as pitch class A.
        let ch = KeyEstimator.chroma(samples, sampleRate: 22050)
        XCTAssertEqual(ch.firstIndex(of: ch.max()!), 9)
    }
}
