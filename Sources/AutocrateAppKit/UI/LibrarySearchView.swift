import SwiftUI
import AutocrateCore

/// The desktop window: search your scanned library, pick a seed, see cross-genre matches.
public struct LibrarySearchView: View {
    @ObservedObject var engine: LibrarySearchEngine
    @State private var query = ""

    public init(engine: LibrarySearchEngine) { self.engine = engine }

    public var body: some View {
        HSplitView {
            searchPane.frame(minWidth: 260)
            matchesPane.frame(minWidth: 300)
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(Theme.bg)
        .task { await engine.load() }
    }

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search your library…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { newValue in engine.search(newValue) }
            if let c = engine.coverage {
                Text("\(c.withCamelot) of \(engine.totalLibraryCount) analyzed")
                    .font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
            }
            if !engine.newSongs.isEmpty {
                NewSongsCard(count: engine.newSongs.count)
            }
            List(engine.results) { entry in
                LibraryResultRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture { if entry.isAnalyzed { engine.selectSeed(entry) } }
            }
        }
        .padding(Theme.panelPadding)
    }

    private var matchesPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let seed = engine.seed {
                Text(seed.title).font(Fonts.body(13)).foregroundStyle(Theme.textPrimary)
                Text("\(seed.camelot?.description ?? "—") · \(seed.bpm.map { String(format: "%.0f BPM", $0) } ?? "—")")
                    .font(Fonts.numerals(14)).foregroundStyle(Theme.accent)
                List(Array(engine.matches.enumerated()), id: \.element.track.id) { idx, c in
                    ShortlistRow(candidate: c, isTop: idx == 0,
                                 onOpen: { engine.reveal(c.track) },
                                 onCopy: { engine.copy(c.track) })
                }
            } else {
                Text("Pick an analyzed song to see matches")
                    .font(Fonts.body(12)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(Theme.panelPadding)
    }
}

/// One row in the search results: analyzed (pickable) or greyed "not analyzed".
private struct LibraryResultRow: View {
    let entry: LibraryEntry
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isAnalyzed ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(entry.isAnalyzed ? Theme.accent : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.track.title).font(Fonts.body(12))
                    .foregroundStyle(entry.isAnalyzed ? Theme.textPrimary : Theme.textSecondary)
                Text(entry.track.artist).font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !entry.isAnalyzed {
                Text("not analyzed").font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
            }
        }
        .opacity(entry.isAnalyzed ? 1 : 0.55)
    }
}
