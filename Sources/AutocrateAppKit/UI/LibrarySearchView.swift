import SwiftUI
import AutocrateCore

/// The desktop window: search your scanned library, pick a seed, see cross-genre matches.
public struct LibrarySearchView: View {
    @ObservedObject var engine: LibrarySearchEngine
    @State private var query = ""
    @State private var filter: CategoryFilter = .all

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
            Picker("Show", selection: $filter) {
                ForEach(CategoryFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .font(Fonts.body(10))
            List {
                if filter.matches(.scanned) {
                    section("SCANNED", engine.results.filter { $0.category == .scanned })
                }
                if filter.matches(.missed) {
                    section("MISSED", engine.results.filter { $0.category == .missed })
                }
                if filter.matches(.notAnalyzed) {
                    section("NOT ANALYZED", engine.results.filter { $0.category == .notAnalyzed })
                }
            }
        }
        .padding(Theme.panelPadding)
    }

    /// One titled section with a count; only `.scanned` rows are tappable. Hidden when empty.
    @ViewBuilder
    private func section(_ title: String, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    LibraryResultRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { if entry.isAnalyzed { engine.selectSeed(entry) } }
                }
            } header: {
                Text("\(title)  (\(entries.count))")
                    .font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
            }
        }
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

/// One row in the search results. `.scanned` is pickable (accent dot, full opacity); `.missed` and
/// `.notAnalyzed` are greyed with a trailing status label.
private struct LibraryResultRow: View {
    let entry: LibraryEntry
    private var pickable: Bool { entry.category == .scanned }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pickable ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(pickable ? Theme.accent : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.track.title).font(Fonts.body(12))
                    .foregroundStyle(pickable ? Theme.textPrimary : Theme.textSecondary)
                Text(entry.track.artist).font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let label = trailingLabel {
                Text(label).font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
            }
        }
        .opacity(pickable ? 1 : 0.55)
    }

    private var trailingLabel: String? {
        switch entry.category {
        case .scanned:     return nil
        case .missed:      return "no key found"
        case .notAnalyzed: return "not scanned"
        }
    }
}

/// Category filter for the search list. `.all` shows every section; the rest show one.
private enum CategoryFilter: CaseIterable, Identifiable {
    case all, scanned, missed, notAnalyzed
    var id: Self { self }
    var label: String {
        switch self {
        case .all:         return "All"
        case .scanned:     return "Scanned"
        case .missed:      return "Missed"
        case .notAnalyzed: return "Not analyzed"
        }
    }
    /// True when a section of `category` should be visible under this filter.
    func matches(_ category: LibraryCategory) -> Bool {
        switch self {
        case .all:         return true
        case .scanned:     return category == .scanned
        case .missed:      return category == .missed
        case .notAnalyzed: return category == .notAnalyzed
        }
    }
}
