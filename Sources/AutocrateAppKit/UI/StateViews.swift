import SwiftUI

/// A centered secondary-text message for empty/error states.
public struct CenteredMessage: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(Fonts.body(12)).foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(24)
    }
}

/// Indeterminate "working" banner shown after the seed appears, before the library scan produces
/// counts (seed lookup + library read).
public struct ProcessingBanner: View {
    let text: String
    public init(_ text: String = "analyzing — finding compatible tracks…") { self.text = text }
    public var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.panelPadding).padding(.vertical, 6)
        .background(Theme.surface)
    }
}

/// Banner shown while the cache is still warming, with a live scan count.
public struct IndexingBanner: View {
    let hydrated: Int
    let total: Int
    public init(hydrated: Int, total: Int) { self.hydrated = hydrated; self.total = total }
    public var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("indexing — \(hydrated) of \(total) scanned, more coming")
                .font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.panelPadding).padding(.vertical, 6)
        .background(Theme.surface)
    }
}
