import SwiftUI

/// About row carrying the mandatory GetSongBPM attribution backlink.
public struct AboutView: View {
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Autocrate").font(Fonts.body(12)).foregroundStyle(Theme.textPrimary)
            Link("BPM & key data by GetSongBPM", destination: URL(string: "https://getsongbpm.com")!)
                .font(Fonts.body(10)).foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.panelPadding)
    }
}
