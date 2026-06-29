public extension Track {
    /// Build a rankable library Track from a cached feature row. Genre is dropped (the desktop
    /// window ranks cross-genre, so genre is unused); Camelot is parsed from the stored string.
    init(feature f: CachedFeature) {
        self.init(id: f.id, title: f.title, artist: f.artist, genre: nil,
                  bpm: f.bpm, camelot: f.camelot.flatMap(CamelotKey.init))
    }
}
