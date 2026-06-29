import SwiftUI
import AppKit
import AutocrateCore

/// Tells the user how to analyze newly-added songs WITHOUT the app making any network call.
/// Analysis runs in the CLI `autocrate-scan` (rate-limited, resumable); the window only detects.
struct NewSongsCard: View {
    let count: Int
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analyze \(count) new song\(count == 1 ? "" : "s")")
                .font(Fonts.body(12)).foregroundStyle(Theme.textPrimary)
            Text("Autocrate is local-first — your tracks are analyzed right here on your Mac, never uploaded. To keep your library cache safe, the scan runs on its own. Quit Autocrate, then run:")
                .font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("swift run autocrate-scan").font(Fonts.numerals(11)).foregroundStyle(Theme.accent)
                Spacer()
                Button(copied ? "Copied" : "Copy") { copyCommand() }
                    .buttonStyle(.plain).font(Fonts.body(10)).foregroundStyle(Theme.accent)
            }
            .padding(6)
            .background(Theme.surface)
            Text("Rate-limited and resumable — safe to stop anytime. Reopen Autocrate when it finishes; your new tracks will be waiting.")
                .font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Theme.surface.opacity(0.5))
        .cornerRadius(6)
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("swift run autocrate-scan", forType: .string)
        copied = true
    }
}
