import Foundation
import ScriptingBridge
import AppKit
import AutocrateCore

/// Reads the user's Music library via ScriptingBridge, and reveals/copies tracks.
public struct LibraryReader {
    public init() {}

    /// Every library track (features nil until hydrated), recently-added first.
    public func readAll() -> [Track] {
        guard let music = MusicApp.shared(),
              let raw = music.value(forKey: "tracks") as? [NSObject] else { return [] }

        let pairs: [(Track, Date)] = raw.compactMap { obj in
            guard let title = obj.value(forKey: "name") as? String,
                  let artist = obj.value(forKey: "artist") as? String else { return nil }
            let genre = obj.value(forKey: "genre") as? String
            let added = obj.value(forKey: "dateAdded") as? Date ?? .distantPast
            let track = Track(id: MusicApp.normalizedId(artist: artist, title: title),
                              title: title, artist: artist, genre: genre, bpm: nil, camelot: nil)
            return (track, added)
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
