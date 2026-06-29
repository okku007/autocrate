import Foundation

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
