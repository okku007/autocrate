import XCTest
@testable import AutocrateCore

/// Returns a fixed CachedFeature regardless of args; counts calls.
private final class StubProvider: FeatureProvider {
    var calls = 0
    let feature: CachedFeature
    init(_ feature: CachedFeature) { self.feature = feature }
    func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        calls += 1
        return CachedFeature(id: id, title: title, artist: artist, bpm: feature.bpm,
                             camelot: feature.camelot, musicalKey: feature.musicalKey,
                             source: feature.source, state: feature.state,
                             fetchedAt: feature.fetchedAt, confidence: feature.confidence)
    }
}

private func feature(bpm: Double?, camelot: String?, source: String, state: LookupState,
                     confidence: Double? = nil) -> CachedFeature {
    CachedFeature(id: "id", title: "T", artist: "A", bpm: bpm, camelot: camelot,
                  musicalKey: nil, source: source, state: state, fetchedAt: 0, confidence: confidence)
}

final class HybridFeatureProviderTests: XCTestCase {
    func test_dspBpmNil_backfillsFromFallbackKeepingDspCamelot() async {
        let dsp = StubProvider(feature(bpm: nil, camelot: "8A", source: "dsp", state: .found, confidence: 0.86))
        let fallback = StubProvider(feature(bpm: 128, camelot: "5A", source: "getsongbpm", state: .found))
        let hybrid = HybridFeatureProvider(dsp: dsp, bpmFallback: fallback)

        let f = await hybrid.lookup(artist: "A", title: "T", id: "id")

        XCTAssertEqual(f.state, .found)
        XCTAssertEqual(f.bpm, 128)            // BPM backfilled from fallback
        XCTAssertEqual(f.camelot, "8A")       // Camelot stays from DSP, not the fallback's 5A
        XCTAssertEqual(f.source, "dsp+api")
        XCTAssertEqual(f.confidence, 0.86)    // DSP key confidence survives the merge
        XCTAssertEqual(fallback.calls, 1)
    }

    func test_dspHasBpm_doesNotCallFallback() async {
        let dsp = StubProvider(feature(bpm: 124, camelot: "8A", source: "dsp", state: .found))
        let fallback = StubProvider(feature(bpm: 128, camelot: "5A", source: "getsongbpm", state: .found))
        let hybrid = HybridFeatureProvider(dsp: dsp, bpmFallback: fallback)

        let f = await hybrid.lookup(artist: "A", title: "T", id: "id")

        XCTAssertEqual(f.bpm, 124)
        XCTAssertEqual(f.camelot, "8A")
        XCTAssertEqual(f.source, "dsp")
        XCTAssertEqual(fallback.calls, 0)     // already complete from DSP
    }

    func test_dspMiss_returnsMissWithoutCallingFallback() async {
        let dsp = StubProvider(feature(bpm: nil, camelot: nil, source: "dsp", state: .miss))
        let fallback = StubProvider(feature(bpm: 128, camelot: "5A", source: "getsongbpm", state: .found))
        let hybrid = HybridFeatureProvider(dsp: dsp, bpmFallback: fallback)

        let f = await hybrid.lookup(artist: "A", title: "T", id: "id")

        XCTAssertEqual(f.state, .miss)
        XCTAssertNil(f.bpm)
        XCTAssertNil(f.camelot)
        XCTAssertEqual(fallback.calls, 0)     // no DSP key → nothing to enrich
    }

    func test_bothBpmNil_keepsDspUnchanged() async {
        let dsp = StubProvider(feature(bpm: nil, camelot: "8A", source: "dsp", state: .found))
        let fallback = StubProvider(feature(bpm: nil, camelot: nil, source: "getsongbpm", state: .miss))
        let hybrid = HybridFeatureProvider(dsp: dsp, bpmFallback: fallback)

        let f = await hybrid.lookup(artist: "A", title: "T", id: "id")

        XCTAssertEqual(f.state, .found)
        XCTAssertNil(f.bpm)                   // fallback had nothing either
        XCTAssertEqual(f.camelot, "8A")
        XCTAssertEqual(f.source, "dsp")       // not "dsp+api" — no API BPM was merged
        XCTAssertEqual(fallback.calls, 1)
    }
}
