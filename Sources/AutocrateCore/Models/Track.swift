import Foundation

/// Outcome of a feature lookup.
/// - `found`: features resolved. `miss`: reached the source, genuinely no data (cache it).
/// - `unavailable`: a transient failure (iTunes 403/429, timeout, offline) — NOT cached, so it's
///   retried next session instead of poisoning the cache with a permanent miss.
/// - `unsure`: reserved (not produced).
public enum LookupState: String, Codable { case found, unsure, miss, unavailable }

/// A track — from the library or the catalog. Features (`bpm`, `camelot`) are nil
/// until hydrated from the cache.
public struct Track: Equatable, Identifiable, Sendable {
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
