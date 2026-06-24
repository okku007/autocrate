/// A Camelot-wheel key: a number 1...12 and a letter A (minor) or B (major).
public struct CamelotKey: Equatable, CustomStringConvertible, Sendable {
    public enum Letter: String, Sendable { case a = "A", b = "B" }
    public let number: Int
    public let letter: Letter

    /// Parses `"8A"`, `"12B"`, case-insensitively. Returns nil for out-of-range or malformed input.
    public init?(_ string: String) {
        let s = string.uppercased()
        guard let last = s.last, let letter = Letter(rawValue: String(last)) else { return nil }
        guard let number = Int(s.dropLast()), (1...12).contains(number) else { return nil }
        self.number = number
        self.letter = letter
    }

    public init(number: Int, letter: Letter) {
        self.number = number
        self.letter = letter
    }

    public var description: String { "\(number)\(letter.rawValue)" }
}
