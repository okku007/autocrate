/// Filters and ranks candidates against a seed (pure). Drops anything outside the genre
/// allowlist, out of the BPM band, harmonically incompatible, missing features, or the seed itself.
public struct CandidatePipeline {
    public static let allowlist: Set<String> = [
        "dance", "electronic", "house", "techno", "trance", "dubstep", "bass", "electronica"
    ]

    public init() {}

    public func shortlist(seed: Track, candidates: [Track],
                          applyGenreAllowlist: Bool = true) -> [ScoredCandidate] {
        guard let seedBPM = seed.bpm, let seedKey = seed.camelot else { return [] }

        let scored: [ScoredCandidate] = candidates.compactMap { c -> ScoredCandidate? in
            guard c.id != seed.id else { return nil }
            if applyGenreAllowlist {
                guard let genre = c.genre?.lowercased(), Self.allowlist.contains(genre) else { return nil }
            }
            return score(candidate: c, seedBPM: seedBPM, seedKey: seedKey)
        }
        return Ranker.rank(scored)
    }

    /// Discover candidates carry no library genre tag; gate on key only, BPM soft.
    public func shortlistDiscover(seed: Track, candidates: [Track]) -> [ScoredCandidate] {
        guard let seedBPM = seed.bpm, let seedKey = seed.camelot else { return [] }
        let scored: [ScoredCandidate] = candidates.compactMap { c -> ScoredCandidate? in
            guard c.id != seed.id else { return nil }
            return score(candidate: c, seedBPM: seedBPM, seedKey: seedKey)
        }
        return Ranker.rank(scored)
    }

    /// Gates one candidate: key is required and must be harmonically compatible. BPM is soft — a
    /// candidate with no BPM is kept (ranked on key alone), but a present BPM that's out of band is
    /// a real tempo clash and drops the candidate.
    private func score(candidate c: Track, seedBPM: Double, seedKey: CamelotKey) -> ScoredCandidate? {
        guard let key = c.camelot,
              let relation = CamelotWheel.relation(seed: seedKey, candidate: key) else { return nil }
        let bpmMatch: BpmMatch?
        if let bpm = c.bpm {
            guard let m = BpmBand.evaluate(seedBPM: seedBPM, candidateBPM: bpm) else { return nil }
            bpmMatch = m
        } else {
            bpmMatch = nil
        }
        return ScoredCandidate(track: c, relation: relation, bpm: bpmMatch, score: 0)
    }
}
