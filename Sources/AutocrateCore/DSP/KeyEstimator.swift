import Foundation
import Accelerate

/// Estimates musical key (as Camelot) from raw mono samples: an FFT chromagram (12 pitch-class
/// energies) correlated against the Krumhansl–Schmuckler major/minor key profiles. Confidence is
/// the best profile correlation (0...1).
public enum KeyEstimator {
    static let ksMaj: [Double] = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88]
    static let ksMin: [Double] = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17]
    // Pitch-class (C=0 … B=11) → Camelot, for major and minor tonics.
    static let camMaj = ["8B","3B","10B","5B","12B","7B","2B","9B","4B","11B","6B","1B"]
    static let camMin = ["5A","12A","7A","2A","9A","4A","11A","6A","1A","8A","3A","10A"]

    public static func estimate(_ samples: [Float], sampleRate: Double) -> (camelot: CamelotKey, confidence: Double) {
        keyFromChroma(chroma(samples, sampleRate: sampleRate))
    }

    /// Correlates a 12-bin chroma vector against all 24 key profiles; returns the best Camelot key.
    public static func keyFromChroma(_ chroma: [Float]) -> (camelot: CamelotKey, confidence: Double) {
        let v = chroma.map(Double.init)
        var best = (corr: -2.0, tonic: 0, major: true)
        for t in 0..<12 {
            let majRot = (0..<12).map { ksMaj[(($0 - t) % 12 + 12) % 12] }
            let minRot = (0..<12).map { ksMin[(($0 - t) % 12 + 12) % 12] }
            let cm = pearson(v, majRot), cn = pearson(v, minRot)
            if cm > best.corr { best = (cm, t, true) }
            if cn > best.corr { best = (cn, t, false) }
        }
        let cam = CamelotKey(best.major ? camMaj[best.tonic] : camMin[best.tonic])!
        return (cam, max(0, best.corr))
    }

    /// 12-bin chromagram (pitch-class energy, normalized) via windowed FFT frames.
    public static func chroma(_ samples: [Float], sampleRate: Double) -> [Float] {
        let n = 4096, half = 2048
        guard samples.count >= n, let setup = vDSP_create_fftsetup(vDSP_Length(12), FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: 12)
        }
        defer { vDSP_destroy_fftsetup(setup) }
        let log2n = vDSP_Length(12)   // 2^12 = 4096

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        var chroma = [Float](repeating: 0, count: 12)
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var windowed = [Float](repeating: 0, count: n)
        var mags = [Float](repeating: 0, count: half)

        var idx = 0
        while idx + n <= samples.count {
            samples.withUnsafeBufferPointer { sp in
                vDSP_vmul(sp.baseAddress! + idx, 1, window, 1, &windowed, 1, vDSP_Length(n))
            }
            windowed.withUnsafeBytes { raw in
                let cmplx = raw.bindMemory(to: DSPComplex.self)
                realp.withUnsafeMutableBufferPointer { rp in
                    imagp.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        vDSP_ctoz(cmplx.baseAddress!, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                    }
                }
            }
            for k in 1..<half {
                let freq = Double(k) * sampleRate / Double(n)
                if freq < 55 || freq > 5000 { continue }
                let pc = (9 + Int((12 * log2(freq / 440)).rounded())) % 12
                chroma[(pc + 12) % 12] += mags[k]
            }
            idx += half   // 50% overlap
        }
        let total = chroma.reduce(0, +)
        if total > 0 { for i in 0..<12 { chroma[i] /= total } }
        return chroma
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<a.count { let x = a[i] - ma, y = b[i] - mb; num += x * y; da += x * x; db += y * y }
        let den = (da * db).squareRoot()
        return den > 0 ? num / den : 0
    }
}
