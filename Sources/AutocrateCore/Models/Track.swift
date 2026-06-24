/// Outcome of a feature lookup. `unsure` is reserved for the future DSP path (not produced in v1).
public enum LookupState: String { case found, unsure, miss }

/// A track — from the library or the catalog. Features (`bpm`, `camelot`) are nil
/// until hydrated from the cache.
public struct Track: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let genre: String?
    public let bpm: Double?
    public let camelot: CamelotKey?

    public init(id: String, title: String, artist: String, genre: String?, bpm: Double?, camelot: CamelotKey?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.genre = genre
        self.bpm = bpm
        self.camelot = camelot
    }
}
