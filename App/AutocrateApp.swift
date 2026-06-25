// Xcode app target entry point. NOT part of the SwiftPM package — it builds only
// inside the macOS app target (it needs an app bundle + Info.plist to run as a
// menu-bar item). Add this file to the Xcode app target; link the AutocrateAppKit
// package product. See App/README.md.
import SwiftUI
import AutocrateAppKit

@main
struct AutocrateApp: App {
    // Owned here (not inside MenuPanelView) so the engine and its @Published state survive the
    // panel being dismissed/rebuilt by MenuBarExtra on every open/close.
    @StateObject private var engine = MatchEngine()

    var body: some Scene {
        MenuBarExtra("Autocrate", systemImage: "waveform") {
            MenuPanelView(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
