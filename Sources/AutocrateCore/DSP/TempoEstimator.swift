import Foundation
import Accelerate

/// Estimates tempo from raw mono samples via a spectral-flux onset envelope and its
/// autocorrelation. Spectral flux (positive frame-to-frame change in the magnitude spectrum)
/// catches timbral/harmonic attacks that a plain energy envelope misses. Returns the BPM
/// (octave-folded into `band`) and a 0...1 confidence (autocorrelation peak strength); low
/// confidence means "no clear beat" — callers should drop the BPM rather than trust it.
public enum TempoEstimator {
    public static func estimate(_ samples: [Float], sampleRate: Double,
                                band: ClosedRange<Double> = 90...180) -> (bpm: Double, confidence: Double) {
        let n = 1024, hop = 256, half = 512
        guard samples.count > n + hop * 4,
              let setup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2)) else { return (0, 0) }
        defer { vDSP_destroy_fftsetup(setup) }
        let log2n = vDSP_Length(10)   // 2^10 = 1024

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        // Spectral-flux onset envelope: sum of positive magnitude changes between successive frames.
        let nFrames = (samples.count - n) / hop + 1
        var prevMag = [Float](repeating: 0, count: half)
        var curMag = [Float](repeating: 0, count: half)
        var flux = [Double](repeating: 0, count: nFrames)
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var windowed = [Float](repeating: 0, count: n)

        for fIdx in 0..<nFrames {
            let base = fIdx * hop
            samples.withUnsafeBufferPointer { sp in
                vDSP_vmul(sp.baseAddress! + base, 1, window, 1, &windowed, 1, vDSP_Length(n))
            }
            windowed.withUnsafeBytes { raw in
                let cmplx = raw.bindMemory(to: DSPComplex.self)
                realp.withUnsafeMutableBufferPointer { rp in
                    imagp.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        vDSP_ctoz(cmplx.baseAddress!, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &curMag, 1, vDSP_Length(half))
                    }
                }
            }
            if fIdx > 0 {
                var s = 0.0
                for k in 0..<half { let d = curMag[k] - prevMag[k]; if d > 0 { s += Double(d) } }
                flux[fIdx] = s
            }
            swap(&prevMag, &curMag)
        }

        // Mean-subtract so the autocorrelation measures periodicity, not DC.
        let mean = flux.reduce(0, +) / Double(nFrames)
        for f in 0..<nFrames { flux[f] -= mean }

        func ac(_ lag: Int) -> Double {
            var s = 0.0
            for f in 0..<(nFrames - lag) { s += flux[f] * flux[f + lag] }
            return s
        }
        let ac0 = ac(0)
        guard ac0 > 1e-9 else { return (0, 0) }

        let lagMin = max(1, Int((60.0 * sampleRate / (band.upperBound * Double(hop))).rounded(.down)))
        let lagMax = min(nFrames - 2, Int((60.0 * sampleRate / (band.lowerBound * Double(hop))).rounded(.up)))
        guard lagMax > lagMin else { return (0, 0) }

        var bestLag = lagMin, bestVal = -Double.greatestFiniteMagnitude
        for lag in lagMin...lagMax {
            let v = ac(lag)
            if v > bestVal { bestVal = v; bestLag = lag }
        }

        // Parabolic interpolation around the peak for sub-frame BPM resolution.
        var lag = Double(bestLag)
        if bestLag > lagMin, bestLag < lagMax {
            let a = ac(bestLag - 1), b = bestVal, c = ac(bestLag + 1)
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 { lag += 0.5 * (a - c) / denom }
        }

        let bpm = 60.0 * sampleRate / (lag * Double(hop))
        let confidence = max(0, min(1, bestVal / ac0))
        return (bpm, confidence)
    }
}
