/// Harmonic relationship between a seed key and a candidate key. Perfect > relative > adjacent.
public enum CamelotRelation: Int {
    case adjacent = 1
    case relative = 2
    case perfect  = 3
    public var weight: Int { rawValue }
}
