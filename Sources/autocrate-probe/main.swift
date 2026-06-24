// Headless integration probe for Autocrate.
//
// Exercises the live ScriptingBridge / pipeline path WITHOUT the menu-bar UI, timing each
// stage so we can see exactly where the panel freeze comes from (suspected: the synchronous,
// per-property Apple-Event enumeration of the whole Music library on the main thread).
//
// Run:
//   swift run autocrate-probe          # ScriptingBridge stages only (no network)
//   swift run autocrate-probe --full   # also run the full MatchEngine.refresh() (hits network)
//
// First run prompts for Automation (Music) access, attributed to your terminal app — grant it.

import Foundation
import ScriptingBridge
import AutocrateAppKit
import AutocrateCore

let clock = ContinuousClock()
let wantFull = CommandLine.arguments.contains("--full")
let wantSweep = CommandLine.arguments.contains("--sweep")

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

@discardableResult
func timed<T>(_ label: String, _ body: () -> T) -> T {
    let start = clock.now
    let result = body()
    print("  ⏱  \(pad(label, 32)) \(clock.now - start)")
    return result
}

func rule(_ s: String) { print("\n=== \(s) ===") }

// MARK: - 1. NowPlayingReader (single-object KVC — known to work)

rule("1. NowPlayingReader.read()")
let np = NowPlayingReader()
let state = timed("read()") { np.read() }
switch state {
case .playing(let t): print("  → playing: \(t.artist) – \(t.title)  [genre: \(t.genre ?? "nil")]")
case .stopped:        print("  → stopped / nothing playing")
case .permissionDenied: print("  → PERMISSION DENIED (no Automation grant for Music)")
}

// MARK: - 2. Raw ScriptingBridge library access — staged, to pinpoint the block

rule("2. Raw ScriptingBridge library stages")
guard let music = timed("SBApplication(Music)", { SBApplication(bundleIdentifier: "com.apple.Music") }) else {
    print("  → could not create SBApplication for Music. Stop."); exit(1)
}

// Does plain KVC even reach the `tracks` collection? (H1 question.)
let tracksObj = timed("value(forKey: tracks) [lazy]") { music.value(forKey: "tracks") }
if tracksObj == nil {
    print("  → `tracks` KVC returned nil. SBElementArray NOT reachable via plain KVC → pool always empty (H1).")
} else {
    print("  → `tracks` returned a \(type(of: tracksObj!))")
}

// Materializing the array forces SB to fetch every track specifier (first big cost).
let raw = timed("cast as? [NSObject] [materialize]") { music.value(forKey: "tracks") as? [NSObject] } ?? []
print("  → library track count: \(raw.count)")

// Per-track property reads: each value(forKey:) is a separate Apple-Event round-trip.
if !raw.isEmpty {
    let sample = Array(raw.prefix(5))
    timed("read .name x5 (per-track AE)") {
        for obj in sample { _ = obj.value(forKey: "name") as? String }
    }
    timed("read 4 props x5 (per-track AE)") {
        for obj in sample {
            _ = obj.value(forKey: "name") as? String
            _ = obj.value(forKey: "artist") as? String
            _ = obj.value(forKey: "genre") as? String
            _ = obj.value(forKey: "dateAdded") as? Date
        }
    }
}

// Does Apple Music already hold BPM tags locally? (If so we can skip the API for tagged tracks.)
if !raw.isEmpty, let tracks = music.value(forKey: "tracks") as? SBElementArray {
    let bpms = timed("array(byApplying: bpm) [bulk]") { tracks.array(byApplying: Selector(("bpm"))) }
    let tagged = bpms.compactMap { ($0 as? NSNumber)?.intValue }.filter { $0 > 0 }
    print("  → tracks with a local BPM tag (>0): \(tagged.count) of \(bpms.count)")
}

// MARK: - 3. The real LibraryReader.readAll() — the exact call refresh() blocks on

rule("3. LibraryReader.readAll()  (this is what MatchEngine blocks on)")
print("  (enumerating the WHOLE library synchronously — may take a long time; Ctrl-C to abort)")
let lib = LibraryReader()
let all = timed("readAll()") { lib.readAll() }
print("  → readAll() returned \(all.count) tracks")
if let first = all.first { print("  → newest: \(first.artist) – \(first.title)  [genre: \(first.genre ?? "nil")]") }

// MARK: - 4. Optional: full pipeline (network)

if wantFull {
    rule("4. MatchEngine.refresh()  (--full: hits GetSongBPM + iTunes)")
    let engine = MatchEngine()   // top-level main.swift is implicitly @MainActor
    let s = clock.now
    await engine.refresh()
    print("  ⏱  \(pad("refresh()", 32)) \(clock.now - s)")
    print("  → final PanelState: \(engine.state)")
}

// MARK: - 5. Direct lookup sweep (NO cache) — hunt JSON decode failures

if wantSweep {
    rule("5. Direct lookup sweep (no cache, no sqlite) — hunt decode failures")
    let pool = lib.readAll().filter { ($0.genre?.lowercased()).map(CandidatePipeline.allowlist.contains) ?? false }
    let sample = Array(pool.prefix(80))
    print("  sweeping \(sample.count) of \(pool.count) electronic tracks via GetSongBpmClient.lookup …")
    let client = GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey)
    var found = 0, miss = 0
    for t in sample {
        let f = await client.lookup(artist: t.artist, title: t.title, id: t.id)
        f.state == .found ? (found += 1) : (miss += 1)
        try? await Task.sleep(for: .milliseconds(250))   // be polite to the API
    }
    print("  → swept \(sample.count): found \(found), miss \(miss)  (DECODE FAIL lines above = malformed bodies)")
}

print("\nDone.")
