import SwiftUI
import AppKit
import AutocrateCore

/// The menu-bar panel. Drives MatchEngine and renders each PanelState.
public struct MenuPanelView: View {
    @StateObject private var engine = MatchEngine()
    private let library = LibraryReader()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            content
            Divider().overlay(Theme.border)
            AboutView()
        }
        .frame(width: 340)
        .background(Theme.bg)
        .task { engine.prewarm(); await engine.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch engine.state {
        case .loading:
            CenteredMessage("reading now playing…")
        case .nothingPlaying:
            CenteredMessage("nothing playing")
        case .permissionDenied:
            CenteredMessage("grant Automation access to Music in\nSystem Settings → Privacy & Security")
        case .preparing(let s):
            VStack(spacing: 0) { SeedHeader(seed: s); ProcessingBanner() }
        case .seedMiss(let s):
            VStack(spacing: 0) { SeedHeader(seed: s); CenteredMessage("no BPM/key data for this track") }
        case .noMatches(let s):
            VStack(spacing: 0) { SeedHeader(seed: s); CenteredMessage("no compatible tracks found") }
        case .indexing(let s, let shown, let total, let hydrated):
            VStack(spacing: 0) {
                SeedHeader(seed: s)
                IndexingBanner(hydrated: hydrated, total: total)
                list(library: shown, discover: [])
            }
        case .ready(let s, let matches, let discover):
            VStack(spacing: 0) {
                SeedHeader(seed: s)
                list(library: matches, discover: discover)
            }
        }
    }

    @ViewBuilder private func list(library matches: [ScoredCandidate], discover: [ScoredCandidate]) -> some View {
        ScrollView {
            LazyVStack(spacing: Theme.rowSpacing) {
                ForEach(Array(matches.enumerated()), id: \.element.track.id) { idx, c in
                    ShortlistRow(candidate: c, isTop: idx == 0,
                                 onOpen: { library.revealInMusic(c.track) },
                                 onCopy: { LibraryReader.copyToClipboard(c.track) })
                }
                if !discover.isEmpty {
                    Text("DISCOVER — not in your library")
                        .font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    ForEach(Array(discover.enumerated()), id: \.element.track.id) { _, c in
                        ShortlistRow(candidate: c, isTop: false,
                                     onOpen: { if let url = c.track.appleMusicURL { NSWorkspace.shared.open(url) } },
                                     onCopy: { LibraryReader.copyToClipboard(c.track) })
                    }
                }
            }
            .padding(.horizontal, Theme.panelPadding)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 320)
    }
}
