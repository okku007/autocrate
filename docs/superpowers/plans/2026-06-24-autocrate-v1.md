# Autocrate v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that reads the now-playing Apple Music track and surfaces a ranked shortlist of harmonically- and tempo-compatible tracks to play next.

**Architecture:** Pure matching logic (`Matching/`) with zero I/O is built and unit-tested first. ScriptingBridge readers, the GetSongBPM client, and a GRDB cache are layered on top. A lazy, capped, throttled `FeatureHydrator` populates the cache on demand; a pure `CandidatePipeline` filters and ranks. SwiftUI `MenuBarExtra` renders the panel last.

**Tech Stack:** Swift 5.9+, SwiftUI (`MenuBarExtra`, macOS 13+), ScriptingBridge → Music.app, GetSongBPM REST API, iTunes Search API, GRDB.swift (SQLite), XCTest, os.Logger.

## Global Constraints

- **Platform:** macOS 13.0+ deployment target. Swift 5.9+.
- **Dependencies:** GRDB.swift is the **only** third-party dependency (via SPM). Everything else uses the standard library / system frameworks.
- **Secrets:** the GetSongBPM API key lives in a gitignored `Autocrate/Data/Secrets.swift` (or env var). Never commit the key.
- **Attribution:** the About view MUST contain a visible backlink to `https://getsongbpm.com` — mandatory per the API's terms.
- **Fonts:** `JetBrains Mono` for all body/list/UI text; `Geist Pixel Square` for large numerals only (BPM readout, Camelot badge).
- **Theme tokens (exact):** `bg #0B0B0C`, `surface #141416`, `border rgba(255,255,255,0.06)`, `textPrimary #E8E8E6`, `textSecondary #8A8A85`, one restrained accent.
- **Hardcoded defaults (no settings UI in v1):** genre allowlist = `Dance, Electronic, House, Techno, Trance, Dubstep, Bass, Electronica`; BPM band = ±6%; per-session lookup cap = 50; lookup throttle ≈ 1 req/s.
- **Commit trailer:** end every commit message body with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **TDD:** for all `Matching/`, `Data/`, and `Pipeline/` code, write the failing test first. `Music/` and `UI/` are verified manually (ScriptingBridge + SwiftUI menu-bar resist unit testing).

---

## File Structure

```
Autocrate.xcodeproj
Autocrate/
  App/
    AutocrateApp.swift          MenuBarExtra entry, app lifecycle
    Info.plist                  ATSApplicationFontsPath, NSAppleEventsUsageDescription
  Theme/
    Theme.swift                 color/spacing tokens
    Fonts.swift                 font-name constants + registration helper
  Models/
    Track.swift                 Track, LookupState
    CamelotKey.swift            CamelotKey value type
    MatchResult.swift           BpmMatch, CamelotRelation, ScoredCandidate
  Matching/                     PURE — no I/O
    CamelotWheel.swift          compatibility relation
    KeyToCamelot.swift          musical-key string → CamelotKey
    BpmBand.swift               ±6% band + half/double
    Ranker.swift                scoring + sort
  Music/
    NowPlayingReader.swift      ScriptingBridge: current track
    LibraryReader.swift         ScriptingBridge: all library tracks
    MusicBridge.swift           generated/typed SB protocol header
  Data/
    GetSongBpmClient.swift      search → resolve → bpm/key
    FeatureCache.swift          GRDB store, three-state
    iTunesResolver.swift        confirm catalog availability (phase 6)
    Secrets.swift               (gitignored) API key
  Pipeline/
    FeatureHydrator.swift       lazy/capped/throttled lookup loop
    CandidatePipeline.swift     exclude → band → camelot → rank (pure over hydrated)
  UI/
    MenuPanelView.swift         root panel
    SeedHeader.swift            now-playing header
    ShortlistRow.swift          one candidate row
    StateViews.swift            loading/nothingPlaying/seedMiss/noMatches/indexing/permissionDenied
    AboutView.swift             attribution backlink
AutocrateTests/
  CamelotKeyTests.swift
  CamelotWheelTests.swift
  KeyToCamelotTests.swift
  BpmBandTests.swift
  RankerTests.swift
  FeatureCacheTests.swift
  CandidatePipelineTests.swift
  FeatureHydratorTests.swift
```

---

## Phase 0 — Scaffold

### Task 0: Xcode project + theme + fonts

**Files:**
- Create: `Autocrate.xcodeproj` (via Xcode), `Autocrate/App/AutocrateApp.swift`, `Autocrate/App/Info.plist`, `Autocrate/Theme/Theme.swift`, `Autocrate/Theme/Fonts.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: `enum Theme` with `static let bg/surface/border/textPrimary/textSecondary/accent: Color`; `enum Fonts` with `static let mono/display` name constants + `static func registerBundledFonts()`.

- [ ] **Step 1: Create the Xcode app project (manual)**

In Xcode: File → New → Project → macOS → App. Product name `Autocrate`, Interface SwiftUI, Language Swift, deployment target macOS 13.0. Save inside `/Users/okku/Desktop/Essentials/Projects/autocrate/`. Add a unit-test target `AutocrateTests` (File → New → Target → Unit Testing Bundle) if the template did not create one.

- [ ] **Step 2: Add `.gitignore`**

```gitignore
.DS_Store
xcuserdata/
*.xcuserstate
build/
DerivedData/
Autocrate/Data/Secrets.swift
```

- [ ] **Step 3: Bundle fonts**

Download `JetBrains Mono` and `Geist Pixel Square` `.otf`/`.ttf` files. Drag them into the Xcode project (target membership: Autocrate). In `Info.plist` add `ATSApplicationFontsPath` = `.` (fonts live at bundle resource root).

- [ ] **Step 4: Write `Theme.swift`**

```swift
import SwiftUI

enum Theme {
    static let bg            = Color(hex: 0x0B0B0C)
    static let surface       = Color(hex: 0x141416)
    static let border        = Color.white.opacity(0.06)
    static let textPrimary   = Color(hex: 0xE8E8E6)
    static let textSecondary = Color(hex: 0x8A8A85)
    static let accent        = Color(hex: 0x6EA8FE) // single restrained accent

    static let rowSpacing: CGFloat = 6
    static let panelPadding: CGFloat = 12
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 5: Write `Fonts.swift`**

```swift
import SwiftUI

enum Fonts {
    static let mono    = "JetBrains Mono"      // body / list / UI
    static let display = "Geist Pixel Square"  // large numerals only

    static func body(_ size: CGFloat) -> Font  { .custom(mono, size: size) }
    static func numerals(_ size: CGFloat) -> Font { .custom(display, size: size) }
}
```

- [ ] **Step 6: Write `AutocrateApp.swift`**

```swift
import SwiftUI

@main
struct AutocrateApp: App {
    var body: some Scene {
        MenuBarExtra("Autocrate", systemImage: "waveform") {
            VStack(spacing: 0) {
                Text("Autocrate")
                    .font(Fonts.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(Theme.panelPadding)
            }
            .frame(width: 320)
            .background(Theme.bg)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 7: Build & run — verify**

Run from Xcode (⌘R). Expected: a `waveform` icon appears in the menu bar; clicking it shows a near-black panel reading "Autocrate" in JetBrains Mono.

- [ ] **Step 8: Commit**

```bash
git add -A -- 'autocrate/Autocrate' 'autocrate/Autocrate.xcodeproj' 'autocrate/.gitignore'
git commit -m "feat: scaffold MenuBarExtra app with theme + fonts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 1 — Matching engine (pure logic, TDD)

### Task 1: `CamelotKey` value type

**Files:**
- Create: `Autocrate/Models/CamelotKey.swift`, `AutocrateTests/CamelotKeyTests.swift`

**Interfaces:**
- Produces: `struct CamelotKey: Equatable { enum Letter { case a, b }; let number: Int /*1...12*/; let letter: Letter; init?(_ string: String); var description: String }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class CamelotKeyTests: XCTestCase {
    func test_parsesValidKey() {
        let k = CamelotKey("8A")
        XCTAssertEqual(k?.number, 8)
        XCTAssertEqual(k?.letter, .a)
    }
    func test_parsesTwoDigitNumber() {
        XCTAssertEqual(CamelotKey("12B")?.number, 12)
        XCTAssertEqual(CamelotKey("12B")?.letter, .b)
    }
    func test_isCaseInsensitive() {
        XCTAssertEqual(CamelotKey("8a"), CamelotKey("8A"))
    }
    func test_rejectsOutOfRange() {
        XCTAssertNil(CamelotKey("0A"))
        XCTAssertNil(CamelotKey("13A"))
        XCTAssertNil(CamelotKey("8C"))
        XCTAssertNil(CamelotKey("AA"))
        XCTAssertNil(CamelotKey(""))
    }
    func test_descriptionRoundTrips() {
        XCTAssertEqual(CamelotKey("8A")?.description, "8A")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CamelotKeyTests`
Expected: FAIL — `CamelotKey` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
struct CamelotKey: Equatable, CustomStringConvertible {
    enum Letter: String { case a = "A", b = "B" }
    let number: Int
    let letter: Letter

    init?(_ string: String) {
        let s = string.uppercased()
        guard let last = s.last, let letter = Letter(rawValue: String(last)) else { return nil }
        guard let number = Int(s.dropLast()), (1...12).contains(number) else { return nil }
        self.number = number
        self.letter = letter
    }

    init(number: Int, letter: Letter) {
        self.number = number
        self.letter = letter
    }

    var description: String { "\(number)\(letter.rawValue)" }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CamelotKeyTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Models/CamelotKey.swift autocrate/AutocrateTests/CamelotKeyTests.swift
git commit -m "feat: add CamelotKey value type

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `CamelotWheel` compatibility

**Files:**
- Create: `Autocrate/Models/MatchResult.swift` (adds `CamelotRelation`), `Autocrate/Matching/CamelotWheel.swift`, `AutocrateTests/CamelotWheelTests.swift`

**Interfaces:**
- Consumes: `CamelotKey`.
- Produces: `enum CamelotRelation: Int { case adjacent = 1, relative = 2, perfect = 3; var weight: Int { rawValue } }`; `enum CamelotWheel { static func relation(seed: CamelotKey, candidate: CamelotKey) -> CamelotRelation? }` (nil = incompatible).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class CamelotWheelTests: XCTestCase {
    private func rel(_ a: String, _ b: String) -> CamelotRelation? {
        CamelotWheel.relation(seed: CamelotKey(a)!, candidate: CamelotKey(b)!)
    }
    func test_perfect_sameKey() {
        XCTAssertEqual(rel("8A", "8A"), .perfect)
    }
    func test_relative_sameNumberOppositeLetter() {
        XCTAssertEqual(rel("8A", "8B"), .relative)
    }
    func test_adjacent_plusOne() {
        XCTAssertEqual(rel("8A", "9A"), .adjacent)
    }
    func test_adjacent_minusOne() {
        XCTAssertEqual(rel("8A", "7A"), .adjacent)
    }
    func test_adjacent_wrap_12_to_1() {
        XCTAssertEqual(rel("12A", "1A"), .adjacent)
        XCTAssertEqual(rel("1A", "12A"), .adjacent)
    }
    func test_incompatible_returnsNil() {
        XCTAssertNil(rel("8A", "10A"))   // two steps away
        XCTAssertNil(rel("8A", "9B"))    // diagonal excluded in v1
        XCTAssertNil(rel("8A", "10B"))
    }
    func test_weightOrdering() {
        XCTAssertGreaterThan(CamelotRelation.perfect.weight, CamelotRelation.relative.weight)
        XCTAssertGreaterThan(CamelotRelation.relative.weight, CamelotRelation.adjacent.weight)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CamelotWheelTests`
Expected: FAIL — `CamelotWheel` / `CamelotRelation` not found.

- [ ] **Step 3: Write minimal implementation**

`Autocrate/Models/MatchResult.swift`:
```swift
enum CamelotRelation: Int {
    case adjacent = 1
    case relative = 2
    case perfect  = 3
    var weight: Int { rawValue }
}
```

`Autocrate/Matching/CamelotWheel.swift`:
```swift
enum CamelotWheel {
    /// nil when incompatible. Perfect > relative > adjacent. Diagonal/energy-boost excluded in v1.
    static func relation(seed: CamelotKey, candidate: CamelotKey) -> CamelotRelation? {
        if seed.number == candidate.number {
            return seed.letter == candidate.letter ? .perfect : .relative
        }
        if seed.letter == candidate.letter, isAdjacent(seed.number, candidate.number) {
            return .adjacent
        }
        return nil
    }

    private static func isAdjacent(_ a: Int, _ b: Int) -> Bool {
        let diff = abs(a - b)
        return diff == 1 || diff == 11   // 11 covers the 12↔1 wrap
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CamelotWheelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Models/MatchResult.swift autocrate/Autocrate/Matching/CamelotWheel.swift autocrate/AutocrateTests/CamelotWheelTests.swift
git commit -m "feat: add Camelot compatibility wheel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `KeyToCamelot` conversion

**Files:**
- Create: `Autocrate/Matching/KeyToCamelot.swift`, `AutocrateTests/KeyToCamelotTests.swift`

**Interfaces:**
- Consumes: `CamelotKey`.
- Produces: `enum KeyToCamelot { static func camelot(forMusicalKey key: String) -> CamelotKey? }` — accepts strings like `"A minor"`, `"C major"`, `"F# minor"`, `"Db major"`, enharmonics included; returns nil when unparseable.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class KeyToCamelotTests: XCTestCase {
    private func c(_ s: String) -> String? { KeyToCamelot.camelot(forMusicalKey: s)?.description }

    func test_canonicalMinors() {
        XCTAssertEqual(c("A minor"), "8A")
        XCTAssertEqual(c("E minor"), "9A")
        XCTAssertEqual(c("D minor"), "7A")
    }
    func test_canonicalMajors() {
        XCTAssertEqual(c("C major"), "8B")
        XCTAssertEqual(c("G major"), "9B")
        XCTAssertEqual(c("F major"), "7B")
    }
    func test_sharpsAndFlatsEnharmonic() {
        XCTAssertEqual(c("F# minor"), "11A")
        XCTAssertEqual(c("Gb minor"), "11A")   // enharmonic of F#
        XCTAssertEqual(c("Db major"), "3B")
        XCTAssertEqual(c("C# major"), "3B")    // enharmonic of Db
        XCTAssertEqual(c("Ab minor"), "1A")
        XCTAssertEqual(c("G# minor"), "1A")
    }
    func test_caseAndWhitespaceTolerant() {
        XCTAssertEqual(c("  a   MINOR "), "8A")
        XCTAssertEqual(c("amin"), "8A")
        XCTAssertEqual(c("Cmaj"), "8B")
    }
    func test_unparseableReturnsNil() {
        XCTAssertNil(c("H minor"))
        XCTAssertNil(c(""))
        XCTAssertNil(c("A"))           // no mode
    }
    func test_allTwentyFourAreCovered() {
        let keys = ["C","G","D","A","E","B","F#","Db","Ab","Eb","Bb","F"]
        for k in keys {
            XCTAssertNotNil(c("\(k) major"), "\(k) major")
            XCTAssertNotNil(c("\(k) minor"), "\(k) minor")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/KeyToCamelotTests`
Expected: FAIL — `KeyToCamelot` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
enum KeyToCamelot {
    // Canonical pitch-class index, enharmonics normalized to one spelling.
    private static let pitchClass: [String: Int] = [
        "C": 0, "B#": 0,
        "C#": 1, "DB": 1,
        "D": 2,
        "D#": 3, "EB": 3,
        "E": 4, "FB": 4,
        "F": 5, "E#": 5,
        "F#": 6, "GB": 6,
        "G": 7,
        "G#": 8, "AB": 8,
        "A": 9,
        "A#": 10, "BB": 10,
        "B": 11, "CB": 11
    ]
    // Camelot number for a given pitch class, by mode (Camelot wheel order).
    // major pitch-class -> Camelot number (letter B):
    private static let majorCamelot: [Int: Int] = [
        0: 8, 1: 3, 2: 10, 3: 5, 4: 12, 5: 7, 6: 2, 7: 9, 8: 4, 9: 11, 10: 6, 11: 1
    ]
    // minor pitch-class -> Camelot number (letter A):
    private static let minorCamelot: [Int: Int] = [
        0: 5, 1: 12, 2: 7, 3: 2, 4: 9, 5: 4, 6: 11, 7: 6, 8: 1, 9: 8, 10: 3, 11: 10
    ]

    static func camelot(forMusicalKey key: String) -> CamelotKey? {
        let cleaned = key.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return nil }

        let isMinor: Bool
        let root: String
        if let r = strip(cleaned, suffixes: ["MINOR", "MIN", "M"]) { isMinor = true; root = r }
        else if let r = strip(cleaned, suffixes: ["MAJOR", "MAJ"]) { isMinor = false; root = r }
        else { return nil }

        guard let pc = pitchClass[root.trimmingCharacters(in: .whitespaces)] else { return nil }
        let number = isMinor ? minorCamelot[pc]! : majorCamelot[pc]!
        return CamelotKey(number: number, letter: isMinor ? .a : .b)
    }

    private static func strip(_ s: String, suffixes: [String]) -> String? {
        for suffix in suffixes where s.hasSuffix(suffix) {
            return String(s.dropLast(suffix.count))
        }
        return nil
    }
}
```

> Note: `"C major"` → root `"C"` via the `MAJOR` suffix; bare `"A"` (no mode) returns nil because no suffix matches. `"AMIN"`/`"CMAJ"` work via the `MIN`/`MAJ`/`M` suffixes. The `M` suffix is checked only in the minor branch, after `MINOR`/`MIN`, so `"AM"` → minor.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/KeyToCamelotTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Matching/KeyToCamelot.swift autocrate/AutocrateTests/KeyToCamelotTests.swift
git commit -m "feat: add musical-key to Camelot conversion

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `BpmBand` (±6% + half/double)

**Files:**
- Modify: `Autocrate/Models/MatchResult.swift` (add `BpmMatch`)
- Create: `Autocrate/Matching/BpmBand.swift`, `AutocrateTests/BpmBandTests.swift`

**Interfaces:**
- Produces: `struct BpmMatch: Equatable { let closeness: Double /*0...1, 1=exact*/; let tempoShifted: Bool }`; `enum BpmBand { static let tolerance = 0.06; static func evaluate(seedBPM: Double, candidateBPM: Double) -> BpmMatch? }` (nil = out of band).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class BpmBandTests: XCTestCase {
    func test_exactMatch_closenessOne_notShifted() {
        let m = BpmBand.evaluate(seedBPM: 128, candidateBPM: 128)
        XCTAssertEqual(m?.closeness, 1.0, accuracy: 0.0001)
        XCTAssertEqual(m?.tempoShifted, false)
    }
    func test_withinBand_upperEdge() {
        // 128 * 1.06 = 135.68
        XCTAssertNotNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 135.6))
    }
    func test_withinBand_lowerEdge() {
        // 128 * 0.94 = 120.32
        XCTAssertNotNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 120.4))
    }
    func test_outOfBand_returnsNil() {
        XCTAssertNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 140)) // Skrillex problem
        XCTAssertNil(BpmBand.evaluate(seedBPM: 128, candidateBPM: 110))
    }
    func test_halfTime_passesFlaggedShifted() {
        // 64 * 2 = 128 -> in band
        let m = BpmBand.evaluate(seedBPM: 128, candidateBPM: 64)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.tempoShifted, true)
    }
    func test_doubleTime_passesFlaggedShifted() {
        // 256 / 2 = 128 -> in band
        let m = BpmBand.evaluate(seedBPM: 128, candidateBPM: 256)
        XCTAssertEqual(m?.tempoShifted, true)
    }
    func test_closenessDecreasesWithDistance() {
        let near = BpmBand.evaluate(seedBPM: 128, candidateBPM: 129)!.closeness
        let far  = BpmBand.evaluate(seedBPM: 128, candidateBPM: 134)!.closeness
        XCTAssertGreaterThan(near, far)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/BpmBandTests`
Expected: FAIL — `BpmBand` / `BpmMatch` not found.

- [ ] **Step 3: Write minimal implementation**

Add to `MatchResult.swift`:
```swift
struct BpmMatch: Equatable {
    let closeness: Double   // 0...1, 1 = exact seed BPM
    let tempoShifted: Bool
}
```

`Autocrate/Matching/BpmBand.swift`:
```swift
enum BpmBand {
    static let tolerance = 0.06

    static func evaluate(seedBPM: Double, candidateBPM: Double) -> BpmMatch? {
        guard seedBPM > 0, candidateBPM > 0 else { return nil }
        // Try direct, then half, then double.
        let attempts: [(bpm: Double, shifted: Bool)] = [
            (candidateBPM, false),
            (candidateBPM * 2, true),
            (candidateBPM / 2, true)
        ]
        for a in attempts {
            if let closeness = closenessIfInBand(seed: seedBPM, candidate: a.bpm) {
                return BpmMatch(closeness: closeness, tempoShifted: a.shifted)
            }
        }
        return nil
    }

    private static func closenessIfInBand(seed: Double, candidate: Double) -> Double? {
        let delta = abs(candidate - seed)
        let maxDelta = seed * tolerance
        guard delta <= maxDelta else { return nil }
        return 1 - (delta / maxDelta)   // 1 at exact, 0 at band edge
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/BpmBandTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Models/MatchResult.swift autocrate/Autocrate/Matching/BpmBand.swift autocrate/AutocrateTests/BpmBandTests.swift
git commit -m "feat: add BPM band with half/double-time matching

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `Track` model + `Ranker`

**Files:**
- Create: `Autocrate/Models/Track.swift`
- Modify: `Autocrate/Models/MatchResult.swift` (add `ScoredCandidate`)
- Create: `Autocrate/Matching/Ranker.swift`, `AutocrateTests/RankerTests.swift`

**Interfaces:**
- Consumes: `CamelotKey`, `CamelotRelation`, `BpmMatch`.
- Produces:
  - `enum LookupState: String { case found, unsure, miss }`
  - `struct Track: Equatable, Identifiable { let id: String; let title: String; let artist: String; let genre: String?; let bpm: Double?; let camelot: CamelotKey? }`
  - `struct ScoredCandidate: Equatable { let track: Track; let relation: CamelotRelation; let bpm: BpmMatch; var score: Double }`
  - `enum Ranker { static func score(relation: CamelotRelation, bpm: BpmMatch) -> Double; static func rank(_ candidates: [ScoredCandidate]) -> [ScoredCandidate] }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class RankerTests: XCTestCase {
    private func cand(_ id: String, _ rel: CamelotRelation, closeness: Double, shifted: Bool = false) -> ScoredCandidate {
        ScoredCandidate(
            track: Track(id: id, title: id, artist: "x", genre: "House", bpm: 128, camelot: CamelotKey("8A")),
            relation: rel,
            bpm: BpmMatch(closeness: closeness, tempoShifted: shifted),
            score: 0
        )
    }
    func test_perfectOutranksRelativeOutranksAdjacent() {
        let ranked = Ranker.rank([
            cand("adj", .adjacent, closeness: 1),
            cand("perf", .perfect, closeness: 0.1),
            cand("rel", .relative, closeness: 1)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["perf", "rel", "adj"])
    }
    func test_tieBrokenByBpmCloseness() {
        let ranked = Ranker.rank([
            cand("far", .perfect, closeness: 0.2),
            cand("near", .perfect, closeness: 0.9)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["near", "far"])
    }
    func test_exactRanksAboveTempoShifted_whenOtherwiseEqual() {
        let ranked = Ranker.rank([
            cand("shifted", .perfect, closeness: 0.5, shifted: true),
            cand("exact", .perfect, closeness: 0.5, shifted: false)
        ])
        XCTAssertEqual(ranked.map(\.track.id), ["exact", "shifted"])
    }
    func test_scoreIsPopulated() {
        let ranked = Ranker.rank([cand("a", .perfect, closeness: 1)])
        XCTAssertGreaterThan(ranked[0].score, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/RankerTests`
Expected: FAIL — `Track` / `ScoredCandidate` / `Ranker` not found.

- [ ] **Step 3: Write minimal implementation**

`Autocrate/Models/Track.swift`:
```swift
enum LookupState: String { case found, unsure, miss }

struct Track: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let genre: String?
    let bpm: Double?
    let camelot: CamelotKey?
}
```

Add to `MatchResult.swift`:
```swift
struct ScoredCandidate: Equatable {
    let track: Track
    let relation: CamelotRelation
    let bpm: BpmMatch
    var score: Double
}
```

`Autocrate/Matching/Ranker.swift`:
```swift
enum Ranker {
    /// Camelot weight dominates; BPM closeness (0...1) breaks ties within a weight.
    static func score(relation: CamelotRelation, bpm: BpmMatch) -> Double {
        Double(relation.weight) + bpm.closeness
    }

    static func rank(_ candidates: [ScoredCandidate]) -> [ScoredCandidate] {
        candidates
            .map { var c = $0; c.score = score(relation: c.relation, bpm: c.bpm); return c }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.bpm.tempoShifted != rhs.bpm.tempoShifted { return !lhs.bpm.tempoShifted }
                return lhs.bpm.closeness > rhs.bpm.closeness
            }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/RankerTests`
Expected: PASS.

- [ ] **Step 5: Run the full matching suite & commit**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CamelotKeyTests -only-testing:AutocrateTests/CamelotWheelTests -only-testing:AutocrateTests/KeyToCamelotTests -only-testing:AutocrateTests/BpmBandTests -only-testing:AutocrateTests/RankerTests`
Expected: all PASS.

```bash
git add autocrate/Autocrate/Models/Track.swift autocrate/Autocrate/Models/MatchResult.swift autocrate/Autocrate/Matching/Ranker.swift autocrate/AutocrateTests/RankerTests.swift
git commit -m "feat: add Track model and candidate ranker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 2 — Now-playing reader (manual verification)

### Task 6: `NowPlayingReader` via ScriptingBridge

**Files:**
- Create: `Autocrate/Music/MusicBridge.swift` (typed SB protocol), `Autocrate/Music/NowPlayingReader.swift`
- Modify: `Autocrate/App/Info.plist` (add `NSAppleEventsUsageDescription`)

**Interfaces:**
- Consumes: `Track`.
- Produces:
  - `enum NowPlayingState: Equatable { case playing(Track), stopped, permissionDenied }`
  - `struct NowPlayingReader { func read() -> NowPlayingState }`
  - Seed `Track` has `bpm = nil`, `camelot = nil` here (features filled later by the hydrator); `id` = `normalizedId(artist:title:)`.
  - Produces helper `func normalizedId(artist: String, title: String) -> String` (lowercased, trimmed, `"artist|title"`).

- [ ] **Step 1: Add the Automation usage string to Info.plist**

Add key `NSAppleEventsUsageDescription` = `Autocrate reads the currently playing track from Music to suggest compatible next tracks.`

- [ ] **Step 2: Write the typed ScriptingBridge header**

`Autocrate/Music/MusicBridge.swift` — minimal `@objc` protocols for the Music.app objects used:
```swift
import ScriptingBridge

@objc protocol MusicApplication {
    @objc optional var currentTrack: MusicTrack { get }
    @objc optional var playerState: MusicEPlS { get }
}

@objc protocol MusicTrack {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var genre: String { get }
    @objc optional func reveal()
}

// Player state enum from Music.app's sdef ('kPSP' etc). Stopped == 'kPSS'.
enum MusicEPlS: UInt32 {
    case stopped = 0x6b505353  // 'kPSS'
    case playing = 0x6b505350  // 'kPSP'
    case paused  = 0x6b505370  // 'kPSp'
    case other   = 0
}

extension SBApplication: MusicApplication {}
```

> If the executor prefers, generate the full header via `sdef /System/Applications/Music.app | sdp -fh --basename Music` and use the generated `MusicApplication`/`MusicTrack` instead of this minimal subset. The minimal subset above is sufficient for v1.

- [ ] **Step 3: Write `NowPlayingReader`**

```swift
import ScriptingBridge
import os

struct NowPlayingReader {
    private let log = Logger(subsystem: "dev.moksh.autocrate", category: "nowplaying")

    func read() -> NowPlayingState {
        guard let music = SBApplication(bundleIdentifier: "com.apple.Music") as MusicApplication? else {
            return .permissionDenied
        }
        // Touching a property triggers the TCC prompt / denial.
        guard let state = music.playerState else { return .permissionDenied }
        guard state == .playing || state == .paused else { return .stopped }
        guard let t = music.currentTrack,
              let title = t.name, let artist = t.artist else { return .stopped }

        let track = Track(
            id: normalizedId(artist: artist, title: title),
            title: title,
            artist: artist,
            genre: t.genre,
            bpm: nil,
            camelot: nil
        )
        return .playing(track)
    }

    func normalizedId(artist: String, title: String) -> String {
        "\(artist.lowercased().trimmingCharacters(in: .whitespaces))|\(title.lowercased().trimmingCharacters(in: .whitespaces))"
    }
}

enum NowPlayingState: Equatable {
    case playing(Track)
    case stopped
    case permissionDenied
}
```

- [ ] **Step 4: Manual verification**

Temporarily wire `NowPlayingReader().read()` into a `print`/`Logger` call at app launch. Run the app with Music playing a track. Expected: Console logs the playing track's title/artist/genre. Stop Music → `stopped`. Deny the Automation prompt (or toggle it off in System Settings → Privacy & Security → Automation) → `permissionDenied`.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Music/MusicBridge.swift autocrate/Autocrate/Music/NowPlayingReader.swift autocrate/Autocrate/App/Info.plist
git commit -m "feat: read now-playing track via ScriptingBridge

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 3 — GetSongBPM client + cache (TDD where pure)

### Task 7: `FeatureCache` (GRDB)

**Files:**
- Modify: Xcode project — add GRDB.swift via SPM (`https://github.com/groue/GRDB.swift`, latest).
- Create: `Autocrate/Data/FeatureCache.swift`, `AutocrateTests/FeatureCacheTests.swift`

**Interfaces:**
- Consumes: `LookupState`, `CamelotKey`.
- Produces:
  - `struct CachedFeature: Equatable { let id: String; let title: String; let artist: String; let bpm: Double?; let camelot: String?; let musicalKey: String?; let source: String; let state: LookupState; let fetchedAt: Int }`
  - `final class FeatureCache { init(path: String) throws; func upsert(_ f: CachedFeature) throws; func fetch(id: String) throws -> CachedFeature? }`
  - In-memory test init: `FeatureCache(path: ":memory:")`.

- [ ] **Step 1: Add GRDB dependency**

In Xcode: File → Add Package Dependencies → `https://github.com/groue/GRDB.swift` → add `GRDB` to the Autocrate target.

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class FeatureCacheTests: XCTestCase {
    private func makeCache() throws -> FeatureCache { try FeatureCache(path: ":memory:") }

    private func feature(_ id: String, state: LookupState = .found) -> CachedFeature {
        CachedFeature(id: id, title: "T", artist: "A", bpm: 128, camelot: "8A",
                      musicalKey: "A minor", source: "getsongbpm", state: state, fetchedAt: 1)
    }

    func test_upsertThenFetchRoundTrips() throws {
        let cache = try makeCache()
        try cache.upsert(feature("a|b"))
        XCTAssertEqual(try cache.fetch(id: "a|b"), feature("a|b"))
    }
    func test_fetchMissingReturnsNil() throws {
        let cache = try makeCache()
        XCTAssertNil(try cache.fetch(id: "nope"))
    }
    func test_missStateIsPersisted() throws {
        let cache = try makeCache()
        let miss = CachedFeature(id: "x", title: "T", artist: "A", bpm: nil, camelot: nil,
                                 musicalKey: nil, source: "getsongbpm", state: .miss, fetchedAt: 2)
        try cache.upsert(miss)
        XCTAssertEqual(try cache.fetch(id: "x")?.state, .miss)
    }
    func test_upsertReplacesExisting() throws {
        let cache = try makeCache()
        try cache.upsert(feature("a|b", state: .miss))
        try cache.upsert(feature("a|b", state: .found))
        XCTAssertEqual(try cache.fetch(id: "a|b")?.state, .found)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/FeatureCacheTests`
Expected: FAIL — `FeatureCache` / `CachedFeature` not found.

- [ ] **Step 4: Write minimal implementation**

```swift
import GRDB

struct CachedFeature: Equatable, Codable, FetchableRecord, PersistableRecord {
    let id: String
    let title: String
    let artist: String
    let bpm: Double?
    let camelot: String?
    let musicalKey: String?
    let source: String
    let state: LookupState
    let fetchedAt: Int

    static let databaseTableName = "feature_cache"
    enum Columns: String, CodingKey {
        case id, title, artist, bpm, camelot
        case musicalKey = "musical_key"
        case source, state
        case fetchedAt = "fetched_at"
    }
}

extension LookupState: DatabaseValueConvertible {}

final class FeatureCache {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = path == ":memory:" ? try DatabaseQueue() : try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "feature_cache") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("bpm", .double)
                t.column("camelot", .text)
                t.column("musical_key", .text)
                t.column("source", .text).notNull()
                t.column("state", .text).notNull()
                t.column("fetched_at", .integer).notNull()
            }
        }
        return m
    }

    func upsert(_ f: CachedFeature) throws {
        try dbQueue.write { db in try f.save(db) }
    }
    func fetch(id: String) throws -> CachedFeature? {
        try dbQueue.read { db in try CachedFeature.fetchOne(db, key: id) }
    }
}
```

> Encoding note: with `CodingKeys` mapping `musicalKey`→`musical_key` and `fetchedAt`→`fetched_at`, the struct's `Codable` conformance drives GRDB column names. Use a single `enum CodingKeys: String, CodingKey` (rename `Columns` above to `CodingKeys`) so `FetchableRecord`/`PersistableRecord` pick up the snake_case columns.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/FeatureCacheTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add autocrate/Autocrate/Data/FeatureCache.swift autocrate/AutocrateTests/FeatureCacheTests.swift autocrate/Autocrate.xcodeproj
git commit -m "feat: add GRDB feature cache with three-state result

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: `GetSongBpmClient`

**Files:**
- Create: `Autocrate/Data/GetSongBpmClient.swift`, `Autocrate/Data/Secrets.swift` (gitignored)

**Interfaces:**
- Consumes: `CachedFeature`, `LookupState`, `KeyToCamelot`.
- Produces:
  - `protocol FeatureProvider { func lookup(artist: String, title: String, id: String) async -> CachedFeature }` (always returns a `CachedFeature`; `state` is `.found` or `.miss`).
  - `struct GetSongBpmClient: FeatureProvider` with `init(apiKey: String, session: URLSession = .shared)`.
  - The protocol exists so the hydrator (Task 10) can be tested against a fake provider.

- [ ] **Step 1: Create the gitignored secret**

`Autocrate/Data/Secrets.swift`:
```swift
enum Secrets {
    static let getSongBpmApiKey = "REPLACE_WITH_YOUR_KEY"
}
```
Confirm `git status` does NOT list this file (it is in `.gitignore`).

- [ ] **Step 2: Write the client**

> No unit test: this hits the network and depends on the live API. Verify manually in Step 3. The `FeatureProvider` protocol is what gets tested (via a fake) in Task 10.

```swift
import Foundation
import os

protocol FeatureProvider {
    func lookup(artist: String, title: String, id: String) async -> CachedFeature
}

struct GetSongBpmClient: FeatureProvider {
    let apiKey: String
    var session: URLSession = .shared
    private let log = Logger(subsystem: "dev.moksh.autocrate", category: "getsongbpm")

    func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        let now = Int(Date().timeIntervalSince1970)
        func miss() -> CachedFeature {
            CachedFeature(id: id, title: title, artist: artist, bpm: nil, camelot: nil,
                          musicalKey: nil, source: "getsongbpm", state: .miss, fetchedAt: now)
        }
        guard let song = await search(artist: artist, title: title) else { return miss() }

        let bpm = Double(song.tempo ?? "")
        let camelot = song.keyOf.flatMap { KeyToCamelot.camelot(forMusicalKey: $0) }?.description
        guard bpm != nil || camelot != nil else { return miss() }

        return CachedFeature(id: id, title: title, artist: artist, bpm: bpm, camelot: camelot,
                             musicalKey: song.keyOf, source: "getsongbpm", state: .found, fetchedAt: now)
    }

    // MARK: - Network

    private struct SearchResponse: Decodable { let search: [Song]? }
    private struct Song: Decodable {
        let tempo: String?
        let keyOf: String?
        enum CodingKeys: String, CodingKey { case tempo; case keyOf = "key_of" }
    }

    private func search(artist: String, title: String) async -> Song? {
        let lookup = "song:\(title) artist:\(artist)"
        guard let q = lookup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.getsong.co/search/?api_key=\(apiKey)&type=both&lookup=\(q)")
        else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SearchResponse.self, from: data).search?.first
        } catch {
            log.error("search failed: \(error.localizedDescription)")
            return nil
        }
    }
}
```

> **Confirm against a live response before relying on field names.** GetSongBPM's base host and exact JSON shape (`search` wrapper, `tempo`, `key_of`) must be validated with one real call in Step 3 and adjusted if they differ. `KeyToCamelot` is the source of truth for the Camelot value; if the API returns `open_key` more reliably than `key_of`, add an `open_key` decode path that maps OpenKey→Camelot (Camelot number = ((openKeyNumber + 6) mod 12) + 1, letter d→B / m→A).

- [ ] **Step 3: Manual verification**

Temporarily call `await GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey).lookup(artist: "deadmau5", title: "Strobe", id: "x")` at launch and log the result. Expected: `state == .found`, a plausible `bpm`, and a Camelot value. Try a nonsense title → `state == .miss`. Fix the JSON field mapping if decoding fails.

- [ ] **Step 4: Commit**

```bash
git add autocrate/Autocrate/Data/GetSongBpmClient.swift
git commit -m "feat: add GetSongBPM feature provider client

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 4 — Library pool + hydrator + pipeline

### Task 9: `LibraryReader` via ScriptingBridge

**Files:**
- Modify: `Autocrate/Music/MusicBridge.swift` (add library accessors)
- Create: `Autocrate/Music/LibraryReader.swift`

**Interfaces:**
- Consumes: `Track`, `NowPlayingReader.normalizedId`.
- Produces: `struct LibraryReader { func readAll() -> [Track] }` — every library track with `bpm = nil`, `camelot = nil` (features hydrated later), sorted recently-added first.

- [ ] **Step 1: Extend the bridge header**

Add to `MusicBridge.swift`:
```swift
@objc protocol MusicSource { @objc optional var name: String { get } }

extension MusicApplication {
    // Library tracks are reachable via the app's `tracks` element on the library source.
}

@objc protocol MusicLibraryAccess {
    @objc optional func tracks() -> SBElementArray
}
```
> Generate the full header via `sdef /System/Applications/Music.app | sdp -fh --basename Music` if the minimal subset is insufficient for reaching library tracks; wire `LibraryReader` to the generated `tracks` element. Each track exposes `name`, `artist`, `genre`, and `dateAdded`.

- [ ] **Step 2: Write `LibraryReader`**

```swift
import ScriptingBridge

struct LibraryReader {
    private let np = NowPlayingReader()

    func readAll() -> [Track] {
        guard let music = SBApplication(bundleIdentifier: "com.apple.Music") as MusicApplication?,
              let raw = (music as AnyObject).value(forKey: "tracks") as? [AnyObject] else {
            return []
        }
        let tracks: [(Track, Date)] = raw.compactMap { obj in
            guard let title = obj.value(forKey: "name") as? String,
                  let artist = obj.value(forKey: "artist") as? String else { return nil }
            let genre = obj.value(forKey: "genre") as? String
            let added = obj.value(forKey: "dateAdded") as? Date ?? .distantPast
            let track = Track(id: np.normalizedId(artist: artist, title: title),
                              title: title, artist: artist, genre: genre, bpm: nil, camelot: nil)
            return (track, added)
        }
        return tracks.sorted { $0.1 > $1.1 }.map(\.0)   // recently-added first
    }
}
```

- [ ] **Step 3: Manual verification**

Log `LibraryReader().readAll().prefix(5)` at launch. Expected: the five most-recently-added library tracks, with genres populated. Confirm the count roughly matches the library size.

- [ ] **Step 4: Commit**

```bash
git add autocrate/Autocrate/Music/MusicBridge.swift autocrate/Autocrate/Music/LibraryReader.swift
git commit -m "feat: read full library via ScriptingBridge

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: `FeatureHydrator` (lazy, capped, throttled)

**Files:**
- Create: `Autocrate/Pipeline/FeatureHydrator.swift`, `AutocrateTests/FeatureHydratorTests.swift`

**Interfaces:**
- Consumes: `FeatureCache`, `FeatureProvider`, `CachedFeature`, `Track`, `CamelotKey`.
- Produces:
  - `struct HydratedTrack: Equatable { let track: Track }` where `track.bpm`/`track.camelot` are filled from cache when available.
  - `actor FeatureHydrator { init(cache: FeatureCache, provider: FeatureProvider, cap: Int = 50, throttle: Duration = .seconds(1)); func hydrate(_ tracks: [Track]) async -> [Track] }`
  - Behavior: for each input track, use cached features if present; otherwise fetch via provider (up to `cap` new fetches this call, sleeping `throttle` between fetches), write every result to cache. Returns tracks with `bpm`/`camelot` populated where known (state `.found`); tracks still uncached or `.miss` come back with nil features.

- [ ] **Step 1: Write the failing test (fake provider + injected sleep)**

```swift
import XCTest
@testable import Autocrate

private final class FakeProvider: FeatureProvider {
    var calls = 0
    let bpmByTitle: [String: Double]
    init(_ bpmByTitle: [String: Double]) { self.bpmByTitle = bpmByTitle }
    func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        calls += 1
        if let bpm = bpmByTitle[title] {
            return CachedFeature(id: id, title: title, artist: artist, bpm: bpm, camelot: "8A",
                                 musicalKey: "A minor", source: "fake", state: .found, fetchedAt: 0)
        }
        return CachedFeature(id: id, title: title, artist: artist, bpm: nil, camelot: nil,
                             musicalKey: nil, source: "fake", state: .miss, fetchedAt: 0)
    }
}

final class FeatureHydratorTests: XCTestCase {
    private func track(_ t: String) -> Track {
        Track(id: "a|\(t)", title: t, artist: "a", genre: "House", bpm: nil, camelot: nil)
    }

    func test_fillsFeaturesFromProviderAndPersists() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["x": 128])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        let out = await hydrator.hydrate([track("x")])
        XCTAssertEqual(out.first?.bpm, 128)
        XCTAssertEqual(out.first?.camelot, CamelotKey("8A"))
        XCTAssertEqual(try cache.fetch(id: "a|x")?.state, .found)
    }
    func test_secondCallHitsCacheNotProvider() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["x": 128])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        _ = await hydrator.hydrate([track("x")])
        _ = await hydrator.hydrate([track("x")])
        XCTAssertEqual(provider.calls, 1)   // second call served from cache
    }
    func test_respectsPerSessionCap() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider(["a": 128, "b": 128, "c": 128])
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 2, throttle: .zero)
        _ = await hydrator.hydrate([track("a"), track("b"), track("c")])
        XCTAssertEqual(provider.calls, 2)   // capped
    }
    func test_missComesBackWithNilFeatures() async throws {
        let cache = try FeatureCache(path: ":memory:")
        let provider = FakeProvider([:])     // everything misses
        let hydrator = FeatureHydrator(cache: cache, provider: provider, cap: 10, throttle: .zero)
        let out = await hydrator.hydrate([track("x")])
        XCTAssertNil(out.first?.bpm)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/FeatureHydratorTests`
Expected: FAIL — `FeatureHydrator` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

actor FeatureHydrator {
    private let cache: FeatureCache
    private let provider: FeatureProvider
    private let cap: Int
    private let throttle: Duration

    init(cache: FeatureCache, provider: FeatureProvider, cap: Int = 50, throttle: Duration = .seconds(1)) {
        self.cache = cache
        self.provider = provider
        self.cap = cap
        self.throttle = throttle
    }

    func hydrate(_ tracks: [Track]) async -> [Track] {
        var fetched = 0
        var result: [Track] = []
        for track in tracks {
            if let cached = try? cache.fetch(id: track.id) {
                result.append(apply(cached, to: track))
                continue
            }
            guard fetched < cap else { result.append(track); continue }
            if fetched > 0, throttle > .zero { try? await Task.sleep(for: throttle) }
            let feature = await provider.lookup(artist: track.artist, title: track.title, id: track.id)
            try? cache.upsert(feature)
            fetched += 1
            result.append(apply(feature, to: track))
        }
        return result
    }

    private func apply(_ f: CachedFeature, to track: Track) -> Track {
        Track(id: track.id, title: track.title, artist: track.artist, genre: track.genre,
              bpm: f.state == .found ? f.bpm : nil,
              camelot: f.camelot.flatMap(CamelotKey.init))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/FeatureHydratorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Pipeline/FeatureHydrator.swift autocrate/AutocrateTests/FeatureHydratorTests.swift
git commit -m "feat: add lazy capped throttled feature hydrator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: `CandidatePipeline` (pure filter + rank)

**Files:**
- Create: `Autocrate/Pipeline/CandidatePipeline.swift`, `AutocrateTests/CandidatePipelineTests.swift`

**Interfaces:**
- Consumes: `Track`, `CamelotKey`, `CamelotWheel`, `BpmBand`, `Ranker`, `ScoredCandidate`.
- Produces:
  - `struct CandidatePipeline { static let allowlist: Set<String> = ["dance","electronic","house","techno","trance","dubstep","bass","electronica"]; func shortlist(seed: Track, candidates: [Track]) -> [ScoredCandidate] }`
  - Drops candidates with no genre / genre outside allowlist, no bpm, or no camelot, or the seed itself; keeps those passing BPM band AND Camelot; returns ranked.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Autocrate

final class CandidatePipelineTests: XCTestCase {
    private let pipeline = CandidatePipeline()
    private func seed() -> Track {
        Track(id: "seed", title: "seed", artist: "s", genre: "House", bpm: 128, camelot: CamelotKey("8A"))
    }
    private func cand(_ id: String, genre: String?, bpm: Double?, camelot: String?) -> Track {
        Track(id: id, title: id, artist: "a", genre: genre,
              bpm: bpm, camelot: camelot.flatMap(CamelotKey.init))
    }

    func test_excludesNonAllowlistGenre() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("country", genre: "Country", bpm: 128, camelot: "8A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesOutOfBandBpm() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("skrillex", genre: "Dubstep", bpm: 140, camelot: "8A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesIncompatibleCamelot() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("clash", genre: "House", bpm: 128, camelot: "10A")
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_excludesMissingFeatures() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("noBpm", genre: "House", bpm: nil, camelot: "8A"),
            cand("noKey", genre: "House", bpm: 128, camelot: nil)
        ])
        XCTAssertTrue(out.isEmpty)
    }
    func test_keepsAndRanksCompatible() {
        let out = pipeline.shortlist(seed: seed(), candidates: [
            cand("adjacent", genre: "House", bpm: 128, camelot: "9A"),
            cand("perfect",  genre: "Trance", bpm: 128, camelot: "8A")
        ])
        XCTAssertEqual(out.map(\.track.id), ["perfect", "adjacent"])
    }
    func test_excludesSeedItself() {
        var s = seed()
        s = Track(id: "seed", title: "seed", artist: "s", genre: "House", bpm: 128, camelot: CamelotKey("8A"))
        let out = pipeline.shortlist(seed: s, candidates: [s])
        XCTAssertTrue(out.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CandidatePipelineTests`
Expected: FAIL — `CandidatePipeline` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
struct CandidatePipeline {
    static let allowlist: Set<String> = [
        "dance","electronic","house","techno","trance","dubstep","bass","electronica"
    ]

    func shortlist(seed: Track, candidates: [Track]) -> [ScoredCandidate] {
        guard let seedBPM = seed.bpm, let seedKey = seed.camelot else { return [] }

        let scored: [ScoredCandidate] = candidates.compactMap { c in
            guard c.id != seed.id else { return nil }
            guard let genre = c.genre?.lowercased(),
                  Self.allowlist.contains(genre) else { return nil }
            guard let bpm = c.bpm, let key = c.camelot else { return nil }
            guard let bpmMatch = BpmBand.evaluate(seedBPM: seedBPM, candidateBPM: bpm) else { return nil }
            guard let relation = CamelotWheel.relation(seed: seedKey, candidate: key) else { return nil }
            return ScoredCandidate(track: c, relation: relation, bpm: bpmMatch, score: 0)
        }
        return Ranker.rank(scored)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/CandidatePipelineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Pipeline/CandidatePipeline.swift autocrate/AutocrateTests/CandidatePipelineTests.swift
git commit -m "feat: add candidate filter + rank pipeline

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 5 — Menu-bar UI + theme

### Task 12: `MatchEngine` coordinator

**Files:**
- Create: `Autocrate/Pipeline/MatchEngine.swift`

**Interfaces:**
- Consumes: `NowPlayingReader`, `LibraryReader`, `FeatureHydrator`, `CandidatePipeline`, `FeatureCache`, `GetSongBpmClient`, `FeatureProvider`.
- Produces:
  - `enum PanelState: Equatable { case loading, nothingPlaying, permissionDenied, seedMiss(Track), noMatches(Track), indexing(seed: Track, shown: [ScoredCandidate], total: Int, hydrated: Int), ready(seed: Track, matches: [ScoredCandidate]) }`
  - `@MainActor final class MatchEngine: ObservableObject { @Published var state: PanelState; func refresh() async }`

- [ ] **Step 1: Write `MatchEngine`**

```swift
import Foundation

enum PanelState: Equatable {
    case loading
    case nothingPlaying
    case permissionDenied
    case seedMiss(Track)
    case noMatches(Track)
    case indexing(seed: Track, shown: [ScoredCandidate], total: Int, hydrated: Int)
    case ready(seed: Track, matches: [ScoredCandidate])
}

@MainActor
final class MatchEngine: ObservableObject {
    @Published var state: PanelState = .loading

    private let nowPlaying = NowPlayingReader()
    private let library = LibraryReader()
    private let pipeline = CandidatePipeline()
    private let cache: FeatureCache
    private let hydrator: FeatureHydrator

    init() {
        let dbPath = FeatureCache.defaultPath()
        let cache = try! FeatureCache(path: dbPath)
        self.cache = cache
        self.hydrator = FeatureHydrator(
            cache: cache,
            provider: GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey)
        )
    }

    func refresh() async {
        state = .loading
        switch nowPlaying.read() {
        case .permissionDenied: state = .permissionDenied; return
        case .stopped: state = .nothingPlaying; return
        case .playing(let rawSeed):
            // Hydrate the seed first.
            let seed = (await hydrator.hydrate([rawSeed])).first ?? rawSeed
            guard seed.bpm != nil, seed.camelot != nil else { state = .seedMiss(seed); return }

            let pool = library.readAll().filter {
                ($0.genre?.lowercased()).map(CandidatePipeline.allowlist.contains) ?? false
            }
            let hydrated = await hydrator.hydrate(pool)
            let hydratedCount = hydrated.filter { $0.bpm != nil }.count
            let matches = pipeline.shortlist(seed: seed, candidates: hydrated)

            if hydratedCount < pool.count {
                state = .indexing(seed: seed, shown: matches, total: pool.count, hydrated: hydratedCount)
            } else if matches.isEmpty {
                state = .noMatches(seed)
            } else {
                state = .ready(seed: seed, matches: matches)
            }
        }
    }
}
```

Add to `FeatureCache.swift`:
```swift
extension FeatureCache {
    static func defaultPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Autocrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("features.sqlite").path
    }
}
```

- [ ] **Step 2: Build check**

Run: `xcodebuild build -scheme Autocrate`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add autocrate/Autocrate/Pipeline/MatchEngine.swift autocrate/Autocrate/Data/FeatureCache.swift
git commit -m "feat: add MatchEngine coordinator with panel states

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Panel UI + state views + theme

**Files:**
- Create: `Autocrate/UI/SeedHeader.swift`, `Autocrate/UI/ShortlistRow.swift`, `Autocrate/UI/StateViews.swift`, `Autocrate/UI/MenuPanelView.swift`, `Autocrate/UI/AboutView.swift`
- Modify: `Autocrate/App/AutocrateApp.swift`

**Interfaces:**
- Consumes: `MatchEngine`, `PanelState`, `ScoredCandidate`, `Track`, `Theme`, `Fonts`, `LibraryReader`.
- Produces: `MenuPanelView`, plus row-tap → reveal-in-Music and modifier-click → clipboard behaviors.

- [ ] **Step 1: Add a reveal helper to `LibraryReader`**

```swift
import AppKit

extension LibraryReader {
    func revealInMusic(_ track: Track) {
        guard let music = SBApplication(bundleIdentifier: "com.apple.Music") as MusicApplication?,
              let raw = (music as AnyObject).value(forKey: "tracks") as? [AnyObject] else { return }
        let np = NowPlayingReader()
        for obj in raw {
            guard let title = obj.value(forKey: "name") as? String,
                  let artist = obj.value(forKey: "artist") as? String,
                  np.normalizedId(artist: artist, title: title) == track.id else { continue }
            (obj as AnyObject).perform(Selector(("reveal")))
            NSWorkspace.shared.launchApplication("Music")
            return
        }
    }

    static func copyToClipboard(_ track: Track) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(track.artist) – \(track.title)", forType: .string)
    }
}
```

- [ ] **Step 2: Write `ShortlistRow`**

```swift
import SwiftUI

struct ShortlistRow: View {
    let candidate: ScoredCandidate
    let isTop: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void

    var body: some View {
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
            if candidate.bpm.tempoShifted {
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
```

- [ ] **Step 3: Write `SeedHeader`**

```swift
import SwiftUI

struct SeedHeader: View {
    let seed: Track
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NOW PLAYING").font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
            Text(seed.title).font(Fonts.body(13)).foregroundStyle(Theme.textPrimary)
            Text(seed.artist).font(Fonts.body(11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Text(seed.camelot?.description ?? "—").font(Fonts.numerals(16)).foregroundStyle(Theme.accent)
                Text(seed.bpm.map { String(format: "%.0f BPM", $0) } ?? "— BPM")
                    .font(Fonts.numerals(16)).foregroundStyle(Theme.textPrimary)
            }
            .monospacedDigit()
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.panelPadding)
        .background(Theme.surface)
    }
}
```

- [ ] **Step 4: Write `StateViews`**

```swift
import SwiftUI

struct CenteredMessage: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Fonts.body(12)).foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(24)
    }
}

struct IndexingBanner: View {
    let hydrated: Int
    let total: Int
    var body: some View {
        Text("indexing — \(hydrated) of \(total) scanned, more coming")
            .font(Fonts.body(10)).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.panelPadding).padding(.vertical, 6)
            .background(Theme.surface)
    }
}
```

- [ ] **Step 5: Write `AboutView` (attribution backlink — mandatory)**

```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Autocrate").font(Fonts.body(12)).foregroundStyle(Theme.textPrimary)
            Link("BPM & key data by GetSongBPM", destination: URL(string: "https://getsongbpm.com")!)
                .font(Fonts.body(10)).foregroundStyle(Theme.accent)
        }
        .padding(Theme.panelPadding)
    }
}
```

- [ ] **Step 6: Write `MenuPanelView` (renders every state)**

```swift
import SwiftUI

struct MenuPanelView: View {
    @StateObject private var engine = MatchEngine()
    private let library = LibraryReader()

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider().overlay(Theme.border)
            AboutView()
        }
        .frame(width: 340)
        .background(Theme.bg)
        .task { await engine.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch engine.state {
        case .loading:          CenteredMessage(text: "reading now playing…")
        case .nothingPlaying:   CenteredMessage(text: "nothing playing")
        case .permissionDenied: CenteredMessage(text: "grant Automation access to Music in\nSystem Settings → Privacy & Security")
        case .seedMiss(let s):  SeedHeader(seed: s); CenteredMessage(text: "no BPM/key data for this track")
        case .noMatches(let s): SeedHeader(seed: s); CenteredMessage(text: "no compatible tracks found")
        case .indexing(let s, let shown, let total, let hydrated):
            SeedHeader(seed: s); IndexingBanner(hydrated: hydrated, total: total); list(s, shown)
        case .ready(let s, let matches):
            SeedHeader(seed: s); list(s, matches)
        }
    }

    @ViewBuilder private func list(_ seed: Track, _ matches: [ScoredCandidate]) -> some View {
        ScrollView {
            LazyVStack(spacing: Theme.rowSpacing) {
                ForEach(Array(matches.enumerated()), id: \.element.track.id) { idx, c in
                    ShortlistRow(candidate: c, isTop: idx == 0,
                                 onOpen: { library.revealInMusic(c.track) },
                                 onCopy: { LibraryReader.copyToClipboard(c.track) })
                }
            }
            .padding(.horizontal, Theme.panelPadding)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 320)
    }
}
```

- [ ] **Step 7: Point the app at the panel**

Replace the `MenuBarExtra` body content in `AutocrateApp.swift` with `MenuPanelView()`:
```swift
MenuBarExtra("Autocrate", systemImage: "waveform") {
    MenuPanelView()
}
.menuBarExtraStyle(.window)
```

- [ ] **Step 8: Manual verification — full loop**

Run the app with Music playing a known electronic track. Expected: seed header shows its BPM + Camelot; a ranked shortlist renders; the top row is accent-tinted; tapping a row reveals that track in Music; option-clicking copies "Artist – Title". Cycle the other states: stop Music (nothingPlaying), play a track with no data (seedMiss), deny Automation (permissionDenied), fresh cache (indexing banner).

- [ ] **Step 9: Commit**

```bash
git add autocrate/Autocrate/UI autocrate/Autocrate/App/AutocrateApp.swift autocrate/Autocrate/Music/LibraryReader.swift
git commit -m "feat: assemble menu-bar panel with all states and theme

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 6 — Catalog expand (closes v1)

### Task 14: `iTunesResolver`

**Files:**
- Create: `Autocrate/Data/iTunesResolver.swift`, `AutocrateTests/iTunesResolverTests.swift`

**Interfaces:**
- Produces:
  - `struct CatalogMatch: Equatable { let title: String; let artist: String; let appleMusicURL: URL }`
  - `protocol CatalogResolver { func resolve(artist: String, title: String) async -> CatalogMatch? }`
  - `struct iTunesResolver: CatalogResolver` (live network). Parsing of the iTunes Search response is factored into a pure `static func parse(_ data: Data) -> CatalogMatch?` so it can be unit-tested without network.

- [ ] **Step 1: Write the failing test (pure parse)**

```swift
import XCTest
@testable import Autocrate

final class iTunesResolverTests: XCTestCase {
    func test_parsesFirstResult() {
        let json = """
        {"resultCount":1,"results":[{"trackName":"Strobe","artistName":"deadmau5","trackViewUrl":"https://music.apple.com/x"}]}
        """.data(using: .utf8)!
        let match = iTunesResolver.parse(json)
        XCTAssertEqual(match?.title, "Strobe")
        XCTAssertEqual(match?.artist, "deadmau5")
        XCTAssertEqual(match?.appleMusicURL.absoluteString, "https://music.apple.com/x")
    }
    func test_emptyResultsReturnsNil() {
        let json = #"{"resultCount":0,"results":[]}"#.data(using: .utf8)!
        XCTAssertNil(iTunesResolver.parse(json))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/iTunesResolverTests`
Expected: FAIL — `iTunesResolver` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct CatalogMatch: Equatable {
    let title: String
    let artist: String
    let appleMusicURL: URL
}

protocol CatalogResolver {
    func resolve(artist: String, title: String) async -> CatalogMatch?
}

struct iTunesResolver: CatalogResolver {
    var session: URLSession = .shared

    func resolve(artist: String, title: String) async -> CatalogMatch? {
        let term = "\(artist) \(title)"
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=1&term=\(q)")
        else { return nil }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> CatalogMatch? {
        struct Response: Decodable {
            struct Result: Decodable { let trackName: String; let artistName: String; let trackViewUrl: String }
            let results: [Result]
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data),
              let first = r.results.first, let url = URL(string: first.trackViewUrl) else { return nil }
        return CatalogMatch(title: first.trackName, artist: first.artistName, appleMusicURL: url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Autocrate -only-testing:AutocrateTests/iTunesResolverTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add autocrate/Autocrate/Data/iTunesResolver.swift autocrate/AutocrateTests/iTunesResolverTests.swift
git commit -m "feat: add iTunes catalog resolver

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 15: Discover section (GetSongBPM `/tempo` + `/key` → resolve → pipeline)

**Files:**
- Modify: `Autocrate/Data/GetSongBpmClient.swift` (add catalog search), `Autocrate/Pipeline/MatchEngine.swift` (add discover phase), `Autocrate/UI/MenuPanelView.swift` (render discover section)

**Interfaces:**
- Consumes: `iTunesResolver`/`CatalogResolver`, `GetSongBpmClient`, `CandidatePipeline`, `CamelotKey`.
- Produces:
  - On `Track`: a new last stored property `var appleMusicURL: URL? = nil` (library tracks leave it nil and use reveal; discover tracks carry the catalog deep-link).
  - On `GetSongBpmClient`: `func discover(targetBPM: Double, camelot: CamelotKey) async -> [Track]` — calls `/tempo/{bpm}` and `/key/{camelot}` search, returns candidate tracks with `bpm`/`camelot` populated.
  - On `MatchEngine`: extends `ready`/`indexing` flow to append a `discover` list — candidates confirmed on Apple Music via `CatalogResolver`, run through the same `CandidatePipeline`, shown below library matches.
  - Adds `PanelState` association `discover: [ScoredCandidate]` to the `ready` case: `case ready(seed: Track, matches: [ScoredCandidate], discover: [ScoredCandidate])`.

- [ ] **Step 0: Add the deep-link field to `Track`**

In `Autocrate/Models/Track.swift`, add `appleMusicURL` as the last stored property so the memberwise initializer gains a default and all existing `Track(...)` call sites keep compiling:
```swift
struct Track: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let genre: String?
    let bpm: Double?
    let camelot: CamelotKey?
    var appleMusicURL: URL? = nil
}
```

- [ ] **Step 1: Add catalog search to the client**

```swift
extension GetSongBpmClient {
    /// GetSongBPM tempo + key search for fresh candidates (not necessarily in the user's library).
    func discover(targetBPM: Double, camelot: CamelotKey) async -> [Track] {
        async let byTempo = searchList(path: "tempo", value: String(format: "%.0f", targetBPM))
        async let byKey   = searchList(path: "key", value: camelot.description)
        let combined = await byTempo + byKey
        // De-dupe by normalized id.
        var seen = Set<String>(); var out: [Track] = []
        for t in combined where seen.insert(t.id).inserted { out.append(t) }
        return out
    }

    private func searchList(path: String, value: String) async -> [Track] {
        guard let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.getsong.co/\(path)/?api_key=\(apiKey)&\(path)=\(v)")
        else { return [] }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        struct Wrapper: Decodable {
            struct Item: Decodable {
                let tempo: String?; let keyOf: String?
                let song_title: String?; let artist: Artist?
                struct Artist: Decodable { let name: String? }
                enum CodingKeys: String, CodingKey { case tempo; case keyOf = "key_of"; case song_title; case artist }
            }
            let tempo: [Item]?; let key: [Item]?
        }
        guard let w = try? JSONDecoder().decode(Wrapper.self, from: data) else { return [] }
        let items = (w.tempo ?? []) + (w.key ?? [])
        let np = NowPlayingReader()
        return items.compactMap { item in
            guard let title = item.song_title, let artist = item.artist?.name else { return nil }
            return Track(id: np.normalizedId(artist: artist, title: title), title: title, artist: artist,
                         genre: nil, bpm: item.tempo.flatMap(Double.init),
                         camelot: item.keyOf.flatMap { KeyToCamelot.camelot(forMusicalKey: $0) })
        }
    }
}
```

> Confirm the `/tempo/` and `/key/` response field names against a live call (Step 4) and adjust the `Wrapper`/`Item` decoding to match. Discover candidates have `genre = nil`, so the pipeline's genre gate is bypassed for them (handled in Step 2).

- [ ] **Step 2: Add the discover phase to `MatchEngine`**

Add a discover-specific pipeline call that skips the genre gate (discover tracks have no library genre) but keeps BPM + Camelot gates:
```swift
extension CandidatePipeline {
    /// Discover candidates have no genre tag; gate on BPM + Camelot only.
    func shortlistDiscover(seed: Track, candidates: [Track]) -> [ScoredCandidate] {
        guard let seedBPM = seed.bpm, let seedKey = seed.camelot else { return [] }
        let scored: [ScoredCandidate] = candidates.compactMap { c in
            guard c.id != seed.id, let bpm = c.bpm, let key = c.camelot,
                  let bpmMatch = BpmBand.evaluate(seedBPM: seedBPM, candidateBPM: bpm),
                  let relation = CamelotWheel.relation(seed: seedKey, candidate: key) else { return nil }
            return ScoredCandidate(track: c, relation: relation, bpm: bpmMatch, score: 0)
        }
        return Ranker.rank(scored)
    }
}
```

In `MatchEngine.refresh()`, after computing library `matches`, add (only when not still indexing):
```swift
// Discover: widen beyond the library, confirm each is on Apple Music.
let client = GetSongBpmClient(apiKey: Secrets.getSongBpmApiKey)
let resolver = iTunesResolver()
let raw = await client.discover(targetBPM: seed.bpm!, camelot: seed.camelot!)
let libraryIds = Set(hydrated.map(\.id))
var confirmed: [Track] = []
for t in raw where !libraryIds.contains(t.id) {
    if let m = await resolver.resolve(artist: t.artist, title: t.title) {
        confirmed.append(Track(id: t.id, title: t.title, artist: t.artist, genre: nil,
                               bpm: t.bpm, camelot: t.camelot, appleMusicURL: m.appleMusicURL))
    }
}
let discover = pipeline.shortlistDiscover(seed: seed, candidates: confirmed)
state = .ready(seed: seed, matches: matches, discover: discover)
```
Update the `PanelState.ready` case to carry `discover` and adjust the `indexing`/`noMatches` branches accordingly (no discover while indexing). The library `.ready` path from Task 13 becomes `.ready(seed:matches:discover: [])` until this discover block runs.

- [ ] **Step 3: Render the discover section in `MenuPanelView`**

Under the library list, when `discover` is non-empty, add a labeled section:
```swift
if !discover.isEmpty {
    Text("DISCOVER — not in your library")
        .font(Fonts.body(9)).foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.panelPadding).padding(.top, 8)
    ForEach(Array(discover.enumerated()), id: \.element.track.id) { _, c in
        ShortlistRow(candidate: c, isTop: false,
                     onOpen: { if let url = c.track.appleMusicURL { NSWorkspace.shared.open(url) } },
                     onCopy: { LibraryReader.copyToClipboard(c.track) })
    }
}
```
Discover rows carry `appleMusicURL` (set in Step 2 from `CatalogResolver`), so `onOpen` deep-links via `NSWorkspace.shared.open`. Library rows leave `appleMusicURL` nil and use reveal (Task 13). `import AppKit` at the top of `MenuPanelView.swift` for `NSWorkspace`.

- [ ] **Step 4: Manual verification — full v1 loop**

Run with Music playing. Expected: library matches appear; below them a "DISCOVER" section lists compatible tracks not in the library, each confirmed on Apple Music; tapping a discover row opens it in Apple Music via its `music.apple.com` URL. Confirm de-duplication (no discover row duplicates a library row).

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -scheme Autocrate`
Expected: all unit tests PASS.

- [ ] **Step 6: Commit**

```bash
git add autocrate/Autocrate/Data/GetSongBpmClient.swift autocrate/Autocrate/Pipeline/MatchEngine.swift autocrate/Autocrate/Pipeline/CandidatePipeline.swift autocrate/Autocrate/UI/MenuPanelView.swift autocrate/Autocrate/Models/Track.swift
git commit -m "feat: add catalog discover section (closes v1)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Done criteria (v1 complete)

- Menu-bar icon → click → panel reads the now-playing track, shows its BPM + Camelot, and renders a ranked shortlist of compatible library tracks, plus a Discover section of compatible tracks confirmed on Apple Music.
- All `Matching/`, `Data/` (cache), and `Pipeline/` unit tests pass.
- Every panel state renders: loading, nothingPlaying, permissionDenied, seedMiss, noMatches, indexing, ready.
- Row tap opens the track in Apple Music; option-click copies "Artist – Title".
- About shows the mandatory GetSongBPM backlink.
- Only dependency is GRDB; the API key is not committed.
```
