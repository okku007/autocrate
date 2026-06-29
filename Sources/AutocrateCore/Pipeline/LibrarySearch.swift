import Foundation

/// A library track tagged with whether it has analyzed features (so it can seed a match).
public struct LibraryEntry: Equatable, Identifiable {
    public let track: Track
    public let isAnalyzed: Bool
    public var id: String { track.id }
    public init(track: Track, isAnalyzed: Bool) {
        self.track = track
        self.isAnalyzed = isAnalyzed
    }
}

/// Pure helpers for the desktop window: library search + analyzed-state annotation.
public enum LibrarySearch {
    /// Case-insensitive filter over title + artist. An empty/whitespace query returns the input
    /// unchanged, preserving the caller's order (e.g. recently-added-first from LibraryReader).
    public static func filter(query: String, tracks: [Track]) -> [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }
}

public extension LibrarySearch {
    /// Tag each library track as analyzed (its id is present in `analyzedIDs`) or not.
    static func annotate(tracks: [Track], analyzedIDs: Set<String>) -> [LibraryEntry] {
        tracks.map { LibraryEntry(track: $0, isAnalyzed: analyzedIDs.contains($0.id)) }
    }

    /// Library tracks with no analyzed features yet — what the "analyze new songs" card lists.
    static func newSongs(tracks: [Track], analyzedIDs: Set<String>) -> [Track] {
        tracks.filter { !analyzedIDs.contains($0.id) }
    }
}
