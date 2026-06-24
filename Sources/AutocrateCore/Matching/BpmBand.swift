/// BPM-band matching (pure). A candidate passes within ±6% of the seed, or via
/// half/double-time (×2 or ÷2 lands in band, flagged tempoShifted).
public enum BpmBand {
    public static let tolerance = 0.06

    /// nil when the candidate is out of band at direct, half, and double time.
    public static func evaluate(seedBPM: Double, candidateBPM: Double) -> BpmMatch? {
        guard seedBPM > 0, candidateBPM > 0 else { return nil }
        let attempts: [(bpm: Double, shifted: Bool)] = [
            (candidateBPM, false),
            (candidateBPM * 2, true),
            (candidateBPM / 2, true)
        ]
        for a in attempts {
            if let closeness = closenessIfInBand(seed: seedBPM, candidate: a.bpm) {
                return BpmMatch(closeness: closeness, tempoShifted: a.shifted)
            }
        }
        return nil
    }

    private static func closenessIfInBand(seed: Double, candidate: Double) -> Double? {
        let delta = abs(candidate - seed)
        let maxDelta = seed * tolerance
        guard delta <= maxDelta else { return nil }
        return 1 - (delta / maxDelta)   // 1 at exact, 0 at band edge
    }
}
