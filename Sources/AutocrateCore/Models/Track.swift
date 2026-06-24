import Foundation

/// Outcome of a feature lookup. `unsure` is reserved for the future DSP path (not produced in v1).
public enum LookupState: String, Codable { case found, unsure, miss }

/// A track — from the library or the catalog. Features (`bpm`, `camelot`) are nil
/// until hydrated from the cache.
public struct Track: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let genre: String?
    public let bpm: Double?
    public let camelot: CamelotKey?
    /// Catalog deep-link for discover tracks; nil for library tracks (which use reveal).
    public var appleMusicURL: URL?

    public init(id: String, title: String, artist: String, genre: String?, bpm: Double?,
                camelot: CamelotKey?, appleMusicURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.genre = genre
        self.bpm = bpm
        self.camelot = camelot
        self.appleMusicURL = appleMusicURL
    }
}
