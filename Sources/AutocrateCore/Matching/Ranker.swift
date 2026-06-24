/// Scores and sorts candidates (pure). Camelot weight dominates; BPM closeness
/// breaks ties within a weight; exact tempo ranks above tempo-shifted when otherwise equal.
public enum Ranker {
    public static func score(relation: CamelotRelation, bpm: BpmMatch) -> Double {
        Double(relation.weight) + bpm.closeness
    }

    public static func rank(_ candidates: [ScoredCandidate]) -> [ScoredCandidate] {
        candidates
            .map { var c = $0; c.score = score(relation: c.relation, bpm: c.bpm); return c }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.bpm.tempoShifted != rhs.bpm.tempoShifted { return !lhs.bpm.tempoShifted }
                return lhs.bpm.closeness > rhs.bpm.closeness
            }
    }
}
