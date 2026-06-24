import Foundation
import ScriptingBridge
import os
import AutocrateCore

/// The current state of Music.app playback for seeding.
public enum NowPlayingState: Equatable {
    case playing(Track)
    case stopped
    case permissionDenied
}

/// Reads the now-playing track from Music.app via ScriptingBridge (KVC).
/// Touching a property triggers the TCC Automation prompt / denial.
public struct NowPlayingReader {
    private let log = Logger(subsystem: "dev.moksh.autocrate", category: "nowplaying")

    // Music.app player-state OSTypes.
    private static let statePlaying: UInt32 = 0x6b505350 // 'kPSP'
    private static let statePaused:  UInt32 = 0x6b505370 // 'kPSp'

    public init() {}

    public func read() -> NowPlayingState {
        guard let music = MusicApp.shared() else { return .permissionDenied }
        guard let stateNum = music.value(forKey: "playerState") as? NSNumber else {
            return .permissionDenied   // property access blocked → no Automation grant
        }
        let state = stateNum.uint32Value
        guard state == Self.statePlaying || state == Self.statePaused else { return .stopped }

        guard let track = music.value(forKey: "currentTrack") as? NSObject,
              let title = track.value(forKey: "name") as? String,
              let artist = track.value(forKey: "artist") as? String else {
            return .stopped
        }
        let genre = track.value(forKey: "genre") as? String
        return .playing(Track(
            id: MusicApp.normalizedId(artist: artist, title: title),
            title: title, artist: artist, genre: genre, bpm: nil, camelot: nil
        ))
    }
}

/// Shared ScriptingBridge access to Music.app.
enum MusicApp {
    static func shared() -> SBApplication? {
        SBApplication(bundleIdentifier: "com.apple.Music")
    }

    static func normalizedId(artist: String, title: String) -> String {
        "\(artist.lowercased().trimmingCharacters(in: .whitespaces))|\(title.lowercased().trimmingCharacters(in: .whitespaces))"
    }
}
