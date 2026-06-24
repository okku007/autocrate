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

/// Banner shown while the cache is still warming.
public struct IndexingBanner: View {
    let hydrated: Int
    let total: Int
    public init(hydrated: Int, total: Int) { self.hydrated = hydrated; self.total = total }
    public var body: some View {
        Text("indexing — \(hydrated) of \(total) scanned, more coming")
            .font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.panelPadding).padding(.vertical, 6)
            .background(Theme.surface)
    }
}
