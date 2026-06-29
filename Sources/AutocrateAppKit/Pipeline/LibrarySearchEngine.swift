import Foundation
import AutocrateCore

/// Drives the desktop window: local search over the scanned library → pick a seed → cross-genre
/// ranked matches. Fully offline — reads ScriptingBridge once and the shared FeatureCache; it never
/// makes a network call and never touches now-playing.
@MainActor
public final class LibrarySearchEngine: ObservableObject {
    /// Annotated, query-filtered library list for the search-results pane.
    @Published public private(set) var results: [LibraryEntry] = []
    /// The chosen seed (an analyzed track), or nil before a pick.
    @Published public private(set) var seed: Track?
    /// Cross-genre ranked matches for the current seed.
    @Published public private(set) var matches: [ScoredCandidate] = []
    /// Library tracks with no features row yet — surfaced in the "analyze new songs" card.
    @Published public private(set) var newSongs: [Track] = []
    @Published public private(set) var coverage: FeatureCache.Coverage?
    @Published public private(set) var totalLibraryCount = 0
    @Published public private(set) var isLoading = false

    private let cache: FeatureCache
    private let library: LibraryReader
    private let pipeline = CandidatePipeline()

    private var allTracks: [Track] = []          // full library, recently-added-first
    private var analyzedIDs: Set<String> = []
    private var pool: [Track] = []               // analyzed tracks as rankable candidates
    private var query = ""

    public init(cache: FeatureCache, library: LibraryReader = LibraryReader()) {
        self.cache = cache
        self.library = library
    }

    /// Load (or reload) the library + analyzed features. Call on first window open.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        allTracks = await library.readAllAsync()
        totalLibraryCount = allTracks.count
        let features = (try? cache.analyzedFeatures()) ?? []
        analyzedIDs = Set(features.map(\.id))
        pool = features.map(Track.init(feature:))
        coverage = try? cache.coverage()
        newSongs = LibrarySearch.newSongs(tracks: allTracks, analyzedIDs: analyzedIDs)
        applyQuery()
    }

    public func search(_ text: String) {
        query = text
        applyQuery()
    }

    /// Pick an analyzed track as the seed and compute cross-genre matches (genre allowlist off).
    public func selectSeed(_ entry: LibraryEntry) {
        guard entry.isAnalyzed, let f = try? cache.fetch(id: entry.track.id) else { return }
        let seedTrack = Track(feature: f)
        seed = seedTrack
        matches = pipeline.shortlist(seed: seedTrack, candidates: pool, applyGenreAllowlist: false)
    }

    public func reveal(_ track: Track) { library.revealInMusic(track) }
    public func copy(_ track: Track) { LibraryReader.copyToClipboard(track) }

    private func applyQuery() {
        let filtered = LibrarySearch.filter(query: query, tracks: allTracks)
        results = LibrarySearch.annotate(tracks: filtered, analyzedIDs: analyzedIDs)
    }
}
