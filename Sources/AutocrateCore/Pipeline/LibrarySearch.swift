import Foundation

/// How a library track relates to the feature cache.
/// - `scanned`: has a Camelot key — pickable as a seed.
/// - `missed`: the scanner ran but found no key (cached miss) — not pickable.
/// - `notAnalyzed`: no cache row yet — hasn't been scanned.
public enum LibraryCategory: Equatable, Sendable {
    case scanned, missed, notAnalyzed
}

/// A library track tagged with its cache category. Only `.scanned` entries can seed a match.
public struct LibraryEntry: Equatable, Identifiable {
    public let track: Track
    public let category: LibraryCategory
    /// True only for `.scanned` — the entry can be picked as a seed.
    public var isAnalyzed: Bool { category == .scanned }
    public var id: String { track.id }
    public init(track: Track, category: LibraryCategory) {
        self.track = track
        self.category = category
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
    /// Classify each library track: scanned (key present) > missed (scanned, no key) > not analyzed.
    /// `analyzedIDs` and `missedIDs` are disjoint by construction; scanned wins if an id is in both.
    static func classify(tracks: [Track], analyzedIDs: Set<String>,
                         missedIDs: Set<String>) -> [LibraryEntry] {
        tracks.map { t in
            let category: LibraryCategory
            if analyzedIDs.contains(t.id) { category = .scanned }
            else if missedIDs.contains(t.id) { category = .missed }
            else { category = .notAnalyzed }
            return LibraryEntry(track: t, category: category)
        }
    }

    /// Library tracks never scanned (no cache row at all) — what the "analyze new songs" card lists.
    /// Excludes misses: those were already scanned, so a re-run skips them.
    static func notAnalyzed(tracks: [Track], analyzedIDs: Set<String>,
                            missedIDs: Set<String>) -> [Track] {
        tracks.filter { !analyzedIDs.contains($0.id) && !missedIDs.contains($0.id) }
    }

    /// Collapse duplicate library rows that share a normalized id (same artist+title appears more
    /// than once in the Music library), keeping the first occurrence and preserving order. The
    /// feature cache is keyed by this id, so duplicates are the same logical track — and duplicate
    /// ids break SwiftUI `ForEach`/`List` identity (undefined results / hangs on large lists).
    static func dedupeByID(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }
}
