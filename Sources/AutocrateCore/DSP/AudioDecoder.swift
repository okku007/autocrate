import Foundation
import AVFoundation

/// Decodes an audio file (e.g. an Apple preview .m4a) to mono Float samples at a target sample rate,
/// ready for the DSP estimators.
public enum AudioDecoder {
    public enum DecodeError: Error { case openFailed, convertFailed }

    public static func monoSamples(url: URL, sampleRate: Double) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount) else {
            throw DecodeError.openFailed
        }
        try file.read(into: inBuf)

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw DecodeError.convertFailed
        }
        let outCapacity = AVAudioFrameCount(Double(frameCount) * sampleRate / inFormat.sampleRate + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            throw DecodeError.convertFailed
        }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: outBuf, error: &error) { _, inStatus in
            if fed { inStatus.pointee = .endOfStream; return nil }    // feed all input once, then flush
            fed = true
            inStatus.pointee = .haveData
            return inBuf
        }
        if let error { throw error }
        guard status != .error, let ch = outBuf.floatChannelData else { throw DecodeError.convertFailed }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
    }
}
