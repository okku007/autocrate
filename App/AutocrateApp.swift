// Xcode app target entry point. NOT part of the SwiftPM package — it builds only
// inside the macOS app target (it needs an app bundle + Info.plist to run as a
// menu-bar item). Add this file to the Xcode app target; link the AutocrateAppKit
// AND AutocrateCore package products. See App/README.md.
import SwiftUI
import AutocrateCore
import AutocrateAppKit

@main
struct AutocrateApp: App {
    // Both engines share ONE FeatureCache (one SQLite connection to features.sqlite).
    // Owned here (not inside the views) so their @Published state survives MenuBarExtra rebuilds
    // and window open/close.
    @StateObject private var engine: MatchEngine
    @StateObject private var searchEngine: LibrarySearchEngine

    init() {
        let cache = try! FeatureCache(path: MatchEngine.defaultCachePath())
        _engine = StateObject(wrappedValue: MatchEngine(cache: cache))
        _searchEngine = StateObject(wrappedValue: LibrarySearchEngine(cache: cache))
    }

    var body: some Scene {
        MenuBarExtra("Autocrate", systemImage: "waveform") {
            MenuPanelView(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Window("Autocrate", id: "main") {
            LibrarySearchView(engine: searchEngine)
        }
    }
}
