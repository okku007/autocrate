import SwiftUI
import AutocrateCore

/// One ranked candidate row. Tap → open; option-tap → copy.
public struct ShortlistRow: View {
    let candidate: ScoredCandidate
    let isTop: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void

    public init(candidate: ScoredCandidate, isTop: Bool,
                onOpen: @escaping () -> Void, onCopy: @escaping () -> Void) {
        self.candidate = candidate
        self.isTop = isTop
        self.onOpen = onOpen
        self.onCopy = onCopy
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(candidate.track.camelot?.description ?? "—")
                .font(Fonts.numerals(13))
                .foregroundStyle(isTop ? Theme.accent : Theme.textPrimary)
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.track.title).font(Fonts.body(12)).foregroundStyle(Theme.textPrimary)
                Text(candidate.track.artist).font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if candidate.bpm?.tempoShifted == true {
                Text("½×").font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
            }
            Text(candidate.track.bpm.map { String(format: "%.0f", $0) } ?? "—")
                .font(Fonts.numerals(13)).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .simultaneousGesture(TapGesture().modifiers(.option).onEnded { onCopy() })
    }
}
