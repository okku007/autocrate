import Foundation
import ScriptingBridge
import AppKit
import AutocrateCore

/// Reads the user's Music library via ScriptingBridge, and reveals/copies tracks.
public struct LibraryReader: Sendable {
    public init() {}

    /// Off-main-thread `readAll()`. The bulk fetch still does blocking Apple Events, so callers
    /// on `@MainActor` (the panel) must use this to avoid freezing the UI.
    public func readAllAsync() async -> [Track] {
        await Task.detached { self.readAll() }.value
    }

    /// Every library track (features nil until hydrated), recently-added first.
    ///
    /// Reads each property with `arrayByApplyingSelector:` — ONE Apple Event per property for the
    /// whole library — instead of `value(forKey:)` per track (one round-trip each). On a ~1900-track
    /// library this is the difference between ~4 Apple Events and ~8,000 (≈130s → a few seconds).
    public func readAll() -> [Track] {
        guard let music = MusicApp.shared(),
              let tracks = music.value(forKey: "tracks") as? SBElementArray else { return [] }

        let names   = tracks.array(byApplying: Selector(("name")))
        let artists = tracks.array(byApplying: Selector(("artist")))
        let genres  = tracks.array(byApplying: Selector(("genre")))
        let dates   = tracks.array(byApplying: Selector(("dateAdded")))

        let n = names.count
        guard n > 0, artists.count == n else { return [] }   // misaligned bulk fetch → bail

        var pairs: [(Track, Date)] = []
        pairs.reserveCapacity(n)
        for i in 0..<n {
            guard let title = names[i] as? String, !title.isEmpty,
                  let artist = artists[i] as? String, !artist.isEmpty else { continue }
            let genre = (i < genres.count ? genres[i] as? String : nil).flatMap { $0.isEmpty ? nil : $0 }
            let added = (i < dates.count ? dates[i] as? Date : nil) ?? .distantPast
            let track = Track(id: MusicApp.normalizedId(artist: artist, title: title),
                              title: title, artist: artist, genre: genre, bpm: nil, camelot: nil)
            pairs.append((track, added))
        }
        return pairs.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Reveals a library track in Music.app (matched by normalized id).
    public func revealInMusic(_ track: Track) {
        guard let music = MusicApp.shared(),
              let raw = music.value(forKey: "tracks") as? [NSObject] else { return }
        for obj in raw {
            guard let title = obj.value(forKey: "name") as? String,
                  let artist = obj.value(forKey: "artist") as? String,
                  MusicApp.normalizedId(artist: artist, title: title) == track.id else { continue }
            obj.perform(Selector(("reveal")))
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
            return
        }
    }

    public static func copyToClipboard(_ track: Track) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(track.artist) – \(track.title)", forType: .string)
    }
}
