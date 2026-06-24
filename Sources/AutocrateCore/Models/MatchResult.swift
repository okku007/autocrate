/// Harmonic relationship between a seed key and a candidate key. Perfect > relative > adjacent.
public enum CamelotRelation: Int {
    case adjacent = 1
    case relative = 2
    case perfect  = 3
    public var weight: Int { rawValue }
}

/// Result of evaluating a candidate's BPM against the seed band.
public struct BpmMatch: Equatable {
    public let closeness: Double   // 0...1, 1 = exact seed BPM
    public let tempoShifted: Bool  // true when matched via half/double-time
    public init(closeness: Double, tempoShifted: Bool) {
        self.closeness = closeness
        self.tempoShifted = tempoShifted
    }
}

/// A candidate that passed both gates, with its relationship and a ranking score.
public struct ScoredCandidate: Equatable {
    public let track: Track
    public let relation: CamelotRelation
    public let bpm: BpmMatch
    public var score: Double
    public init(track: Track, relation: CamelotRelation, bpm: BpmMatch, score: Double) {
        self.track = track
        self.relation = relation
        self.bpm = bpm
        self.score = score
    }
}
