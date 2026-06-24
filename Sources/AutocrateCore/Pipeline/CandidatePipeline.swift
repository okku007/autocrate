/// Filters and ranks candidates against a seed (pure). Drops anything outside the genre
/// allowlist, out of the BPM band, harmonically incompatible, missing features, or the seed itself.
public struct CandidatePipeline {
    public static let allowlist: Set<String> = [
        "dance", "electronic", "house", "techno", "trance", "dubstep", "bass", "electronica"
    ]

    public init() {}

    public func shortlist(seed: Track, candidates: [Track]) -> [ScoredCandidate] {
        guard let seedBPM = seed.bpm, let seedKey = seed.camelot else { return [] }

        let scored: [ScoredCandidate] = candidates.compactMap { c in
            guard c.id != seed.id else { return nil }
            guard let genre = c.genre?.lowercased(), Self.allowlist.contains(genre) else { return nil }
            guard let bpm = c.bpm, let key = c.camelot else { return nil }
            guard let bpmMatch = BpmBand.evaluate(seedBPM: seedBPM, candidateBPM: bpm) else { return nil }
            guard let relation = CamelotWheel.relation(seed: seedKey, candidate: key) else { return nil }
            return ScoredCandidate(track: c, relation: relation, bpm: bpmMatch, score: 0)
        }
        return Ranker.rank(scored)
    }
}
