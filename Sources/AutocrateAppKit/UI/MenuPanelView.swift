import SwiftUI
import AppKit
import AutocrateCore

/// The menu-bar panel. Drives MatchEngine and renders each PanelState.
public struct MenuPanelView: View {
    @ObservedObject private var engine: MatchEngine
    private let library = LibraryReader()

    public init(engine: MatchEngine) { self._engine = ObservedObject(wrappedValue: engine) }

    public var body: some View {
        VStack(spacing: 0) {
            content
            Divider().overlay(Theme.border)
            AboutView()
        }
        .frame(width: 340)
        .background(Theme.bg)
        // Poll now-playing while the panel is open so it follows track changes live. This `.task`
        // is cancelled on dismiss (polling stops when closed) — but it only *nudges* the engine;
        // the actual refresh runs in the engine's own retained Task, which is NOT cancelled here,
        // so closing mid-scan still doesn't restart work. refreshIfNeeded() is a cheap local read
        // that no-ops unless the track actually changed.
        .task {
            while !Task.isCancelled {
                engine.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(2))
            }
        }
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
            VStack(spacing: 0) { SeedHeader(seed: s, canRefresh: engine.canManualRefresh, onRefresh: { engine.forceRefresh() }); ProcessingBanner() }
        case .seedMiss(let s):
            VStack(spacing: 0) { SeedHeader(seed: s, canRefresh: engine.canManualRefresh, onRefresh: { engine.forceRefresh() }); CenteredMessage("no BPM/key data for this track") }
        case .noMatches(let s):
            VStack(spacing: 0) { SeedHeader(seed: s, canRefresh: engine.canManualRefresh, onRefresh: { engine.forceRefresh() }); CenteredMessage("no compatible tracks found") }
        case .indexing(let s, let shown, let total, let hydrated):
            VStack(spacing: 0) {
                SeedHeader(seed: s, canRefresh: engine.canManualRefresh, onRefresh: { engine.forceRefresh() })
                IndexingBanner(hydrated: hydrated, total: total)
                list(library: shown, discover: [])
            }
        case .ready(let s, let matches, let discover):
            VStack(spacing: 0) {
                SeedHeader(seed: s, canRefresh: engine.canManualRefresh, onRefresh: { engine.forceRefresh() })
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
        // Fixed (not max) height: the list keeps a stable viewport so the panel doesn't collapse to a
        // sliver with one result, and doesn't resize on every streamed match. Scrolls when it overflows.
        .frame(height: 320)
    }
}
