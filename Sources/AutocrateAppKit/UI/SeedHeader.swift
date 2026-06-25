import SwiftUI
import AutocrateCore

/// The now-playing seed: title/artist + its BPM and Camelot, with a manual refresh control.
public struct SeedHeader: View {
    let seed: Track
    let canRefresh: Bool
    let onRefresh: () -> Void

    public init(seed: Track, canRefresh: Bool = false, onRefresh: @escaping () -> Void = {}) {
        self.seed = seed
        self.canRefresh = canRefresh
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("NOW PLAYING").font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(canRefresh ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!canRefresh)
                .help("Refresh (rate-limited)")
            }
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
