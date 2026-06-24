/// Scores and sorts candidates (pure). Camelot weight dominates; BPM closeness is a soft bonus
/// that breaks ties within a weight. A missing BPM contributes 0 (skipped, not penalized), so a
/// tempo-confirmed candidate ranks above a key-only one of the same relation, and exact tempo ranks
/// above tempo-shifted when otherwise equal.
public enum Ranker {
    public static func score(relation: CamelotRelation, bpm: BpmMatch?) -> Double {
        Double(relation.weight) + (bpm?.closeness ?? 0)
    }

    public static func rank(_ candidates: [ScoredCandidate]) -> [ScoredCandidate] {
        candidates
            .map { var c = $0; c.score = score(relation: c.relation, bpm: c.bpm); return c }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                // A tempo-confirmed candidate outranks a key-only one at equal score.
                if (lhs.bpm == nil) != (rhs.bpm == nil) { return lhs.bpm != nil }
                guard let l = lhs.bpm, let r = rhs.bpm else { return false }
                if l.tempoShifted != r.tempoShifted { return !l.tempoShifted }
                return l.closeness > r.closeness
            }
    }
}
