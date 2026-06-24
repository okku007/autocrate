import SwiftUI
import AutocrateCore

/// The now-playing seed: title/artist + its BPM and Camelot.
public struct SeedHeader: View {
    let seed: Track
    public init(seed: Track) { self.seed = seed }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NOW PLAYING").font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
            Text(seed.title).font(Fonts.body(13)).foregroundStyle(Theme.textPrimary)
            Text(seed.artist).font(Fonts.body(11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Text(seed.camelot?.description ?? "—").font(Fonts.numerals(16)).foregroundStyle(Theme.accent)
                Text(seed.bpm.map { String(format: "%.0f BPM", $0) } ?? "— BPM")
                    .font(Fonts.numerals(16)).foregroundStyle(Theme.textPrimary)
            }
            .monospacedDigit()
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.panelPadding)
        .background(Theme.surface)
    }
}
