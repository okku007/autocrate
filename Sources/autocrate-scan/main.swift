// Whole-library feature scanner. Reads the Music library via ScriptingBridge, resolves each track's
// 30s preview clip via iTunes Search (existing iTunesResolver: 3s shared rate-limiter + circuit
// breaker), runs on-device DSP for Camelot key (+ best-effort BPM), and warms the same
// features.sqlite the app reads.
//
// Run:  swift run autocrate-scan [--force] [--genre <name>] [--concurrency <n>] [--retry-misses]
// First run prompts for Automation (Music) access, attributed to your terminal — grant it.
// A full cold scan (~1935 tracks) takes ~1.5-2 hrs at the 3s iTunes pacing. It is RESUMABLE:
// Ctrl-C any time and re-run; analyzed tracks are skipped. Refuses to run while the app is open.

import Foundation
import AutocrateAppKit
import AutocrateCore

let args = CommandLine.arguments
func flag(_ name: String) -> Bool { args.contains(name) }
func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let force = flag("--force")
let retryMisses = flag("--retry-misses")
let genre = value("--genre")?.lowercased()
let concurrency = value("--concurrency").flatMap(Int.init) ?? 4

if !force && AppRunningGuard.isAppRunning() {
    print("⚠️  Autocrate app is running. Quit it first (it holds the cache open), or pass --force.")
    exit(1)
}

// Cache path: ~/Library/Application Support/Autocrate/features.sqlite
let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Autocrate", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let cachePath = dir.appendingPathComponent("features.sqlite").path
let cache = try FeatureCache(path: cachePath)

print("Reading library …")
var pool = LibraryReader().readAll()
if let genre { pool = pool.filter { ($0.genre?.lowercased()) == genre } }
print("\(pool.count) tracks to consider (genre filter: \(genre ?? "none")).")
print("iTunes pacing is ~3s/track; a full cold scan can take 1.5-2 hrs. Ctrl-C any time — it resumes.")

// On-device DSP over Apple's preview clips, resolved via the existing iTunesResolver (3s limiter + breaker).
let provider = PreviewDSPProvider(resolver: iTunesResolver())

// warmAll ignores cap/throttle (pacing is the resolver's job); values here are inert.
// Skip rows already analyzed by DSP; with --retry-misses, only trust found rows (re-fetch misses).
// The predicate is inlined in the @Sendable parameter position so it's typed @Sendable contextually.
let hydrator = FeatureHydrator(
    cache: cache, provider: provider, cap: .max, throttle: .zero,
    acceptsCached: { f in
        guard ["dsp", "dsp+api"].contains(f.source) else { return false }
        return retryMisses ? f.state == .found : true
    })

let start = Date()
await hydrator.warmAll(pool, concurrency: concurrency) { t in
    let eta = ScanProgress.etaSeconds(scanned: t.scanned, total: t.total,
                                      elapsed: Date().timeIntervalSince(start))
    FileHandle.standardError.write(Data(
        "\r\(t.scanned)/\(t.total)  found \(t.found)  miss \(t.missed)  eta \(ScanProgress.format(eta))   ".utf8))
}
print("")   // newline after the \r progress line

let cov = try cache.coverage()
print("Cache: \(cov.rows) rows — key \(cov.withCamelot), bpm \(cov.withBpm).")
if await iTunesResolver.sharedBreaker.isOpen {
    print("⚠️  iTunes rate-limited mid-run (circuit breaker open) — results are PARTIAL. Wait ~30 min and re-run; analyzed tracks are skipped.")
} else {
    print("Done.")
}
print("Spot-check estimator accuracy with: CLIPS=/path/to/known/clips swift run autocrate-dsp-probe")
