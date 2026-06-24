import Foundation

/// Estimates tempo from raw mono samples via an energy-flux onset envelope and its
/// autocorrelation. Returns the BPM (octave-folded into `band`) and a 0...1 confidence
/// (autocorrelation peak strength). Low confidence means "no clear beat" — callers should
/// drop the BPM rather than trust it.
public enum TempoEstimator {
    public static func estimate(_ samples: [Float], sampleRate: Double,
                                band: ClosedRange<Double> = 90...180) -> (bpm: Double, confidence: Double) {
        let hop = 256
        guard samples.count > hop * 8 else { return (0, 0) }
        let nFrames = samples.count / hop

        // Onset envelope: per-frame energy, then half-wave-rectified first difference (attacks).
        var energy = [Double](repeating: 0, count: nFrames)
        for f in 0..<nFrames {
            var e = 0.0
            let base = f * hop
            for i in 0..<hop { let v = Double(samples[base + i]); e += v * v }
            energy[f] = e
        }
        var flux = [Double](repeating: 0, count: nFrames)
        for f in 1..<nFrames { flux[f] = max(0, energy[f] - energy[f - 1]) }

        // Mean-subtract so the autocorrelation measures periodicity, not DC (kills noise/tone bias).
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
