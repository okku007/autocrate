/// Converts a musical-key string (e.g. "A minor", "Db major", "F# minor") to a CamelotKey.
/// Enharmonic spellings are normalized. Returns nil when the key cannot be parsed.
public enum KeyToCamelot {
    // Pitch-class index 0...11, enharmonics collapsed to one spelling.
    private static let pitchClass: [String: Int] = [
        "C": 0, "B#": 0,
        "C#": 1, "DB": 1,
        "D": 2,
        "D#": 3, "EB": 3,
        "E": 4, "FB": 4,
        "F": 5, "E#": 5,
        "F#": 6, "GB": 6,
        "G": 7,
        "G#": 8, "AB": 8,
        "A": 9,
        "A#": 10, "BB": 10,
        "B": 11, "CB": 11
    ]
    // Major pitch-class -> Camelot number (letter B).
    private static let majorCamelot: [Int: Int] = [
        0: 8, 1: 3, 2: 10, 3: 5, 4: 12, 5: 7, 6: 2, 7: 9, 8: 4, 9: 11, 10: 6, 11: 1
    ]
    // Minor pitch-class -> Camelot number (letter A).
    private static let minorCamelot: [Int: Int] = [
        0: 5, 1: 12, 2: 7, 3: 2, 4: 9, 5: 4, 6: 11, 7: 6, 8: 1, 9: 8, 10: 3, 11: 10
    ]

    /// Converts GetSongBPM's OpenKey notation ("6m", "9d") to a CamelotKey.
    /// m = minor (Camelot A), d = major (Camelot B). Camelot number = ((n + 6) mod 12) + 1.
    public static func camelot(forOpenKey openKey: String) -> CamelotKey? {
        let s = openKey.trimmingCharacters(in: .whitespaces).lowercased()
        guard let last = s.last, last == "m" || last == "d" else { return nil }
        guard let n = Int(s.dropLast()), (1...12).contains(n) else { return nil }
        let number = ((n + 6) % 12) + 1
        return CamelotKey(number: number, letter: last == "m" ? .a : .b)
    }

    public static func camelot(forMusicalKey key: String) -> CamelotKey? {
        let cleaned = key.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return nil }

        let isMinor: Bool
        let root: String
        if let r = strip(cleaned, suffixes: ["MINOR", "MIN", "M"]) { isMinor = true; root = r }
        else if let r = strip(cleaned, suffixes: ["MAJOR", "MAJ"]) { isMinor = false; root = r }
        else { return nil }

        guard let pc = pitchClass[root.trimmingCharacters(in: .whitespaces)] else { return nil }
        let number = isMinor ? minorCamelot[pc]! : majorCamelot[pc]!
        return CamelotKey(number: number, letter: isMinor ? .a : .b)
    }

    private static func strip(_ s: String, suffixes: [String]) -> String? {
        for suffix in suffixes where s.hasSuffix(suffix) {
            return String(s.dropLast(suffix.count))
        }
        return nil
    }
}
