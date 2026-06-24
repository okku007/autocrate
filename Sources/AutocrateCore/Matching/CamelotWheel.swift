/// Camelot compatibility rules (pure). Perfect > relative > adjacent.
/// Energy-boost (+2) and diagonal moves are deliberately excluded from v1.
public enum CamelotWheel {
    /// nil when the candidate is harmonically incompatible with the seed.
    public static func relation(seed: CamelotKey, candidate: CamelotKey) -> CamelotRelation? {
        if seed.number == candidate.number {
            return seed.letter == candidate.letter ? .perfect : .relative
        }
        if seed.letter == candidate.letter, isAdjacent(seed.number, candidate.number) {
            return .adjacent
        }
        return nil
    }

    private static func isAdjacent(_ a: Int, _ b: Int) -> Bool {
        let diff = abs(a - b)
        return diff == 1 || diff == 11   // 11 covers the 12<->1 wrap
    }
}
