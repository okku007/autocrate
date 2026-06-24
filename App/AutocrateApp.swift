// Xcode app target entry point. NOT part of the SwiftPM package — it builds only
// inside the macOS app target (it needs an app bundle + Info.plist to run as a
// menu-bar item). Add this file to the Xcode app target; link the AutocrateAppKit
// package product. See App/README.md.
import SwiftUI
import AutocrateAppKit

@main
struct AutocrateApp: App {
    var body: some Scene {
        MenuBarExtra("Autocrate", systemImage: "waveform") {
            MenuPanelView()
        }
        .menuBarExtraStyle(.window)
    }
}
