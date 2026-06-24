import XCTest
@testable import AutocrateCore

private struct FakeResolver: CatalogResolver {
    var match: CatalogMatch?
    var error: Error?
    func resolve(artist: String, title: String) async throws -> CatalogMatch? {
        if let error { throw error }
        return match
    }
}

private struct FakeLoader: PreviewSampleLoader {
    var samples: [Float]
    func samples(for url: URL) async throws -> [Float] { samples }
}

private struct ThrowingLoader: PreviewSampleLoader {
    func samples(for url: URL) async throws -> [Float] { throw URLError(.timedOut) }
}

final class PreviewDSPProviderTests: XCTestCase {
    private func clickTrack(bpm: Double, seconds: Double, sr: Double) -> [Float] {
        var s = [Float](repeating: 0, count: Int(seconds * sr))
        let period = Int(sr * 60 / bpm)
        var i = 0
        while i < s.count { for j in 0..<min(64, s.count - i) { s[i+j] = 1 - Float(j)/64 }; i += period }
        return s
    }
    private func match(preview: String?) -> CatalogMatch {
        CatalogMatch(title: "T", artist: "A", appleMusicURL: URL(string: "https://music.apple.com/x")!,
                     previewUrl: preview.flatMap(URL.init(string:)))
    }

    func test_noCatalogMatchIsMiss() async {
        let p = PreviewDSPProvider(resolver: FakeResolver(match: nil), loader: FakeLoader(samples: []))
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        XCTAssertEqual(f.state, .miss)
    }

    func test_noPreviewUrlIsMiss() async {
        let p = PreviewDSPProvider(resolver: FakeResolver(match: match(preview: nil)), loader: FakeLoader(samples: []))
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        XCTAssertEqual(f.state, .miss)
    }

    func test_resolverFailureIsUnavailableNotMiss() async {
        // iTunes 403/timeout etc. → transient: must NOT be cached as a permanent miss.
        let p = PreviewDSPProvider(resolver: FakeResolver(match: nil, error: URLError(.timedOut)),
                                   loader: FakeLoader(samples: []))
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        XCTAssertEqual(f.state, .unavailable)
    }

    func test_clipDownloadFailureIsUnavailable() async {
        let p = PreviewDSPProvider(resolver: FakeResolver(match: match(preview: "https://x/p.m4a")),
                                   loader: ThrowingLoader())
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        XCTAssertEqual(f.state, .unavailable)
    }

    func test_clearBeatYieldsFoundWithBpmAndKey() async {
        let samples = clickTrack(bpm: 120, seconds: 8, sr: 22050)
        let p = PreviewDSPProvider(resolver: FakeResolver(match: match(preview: "https://x/p.m4a")),
                                   loader: FakeLoader(samples: samples))
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        XCTAssertEqual(f.state, .found)
        XCTAssertNotNil(f.camelot)                       // key always attempted from DSP
        XCTAssertEqual(f.bpm ?? 0, 120, accuracy: 3)     // clean beat → confident BPM kept
        XCTAssertEqual(f.source, "dsp")
    }

    func test_storesKeyConfidence() async throws {
        let samples = clickTrack(bpm: 120, seconds: 8, sr: 22050)
        let p = PreviewDSPProvider(resolver: FakeResolver(match: match(preview: "https://x/p.m4a")),
                                   loader: FakeLoader(samples: samples))
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        let conf = try XCTUnwrap(f.confidence)            // key confidence persisted for ranking
        XCTAssert((0...1).contains(conf), "confidence \(conf) out of 0...1")
    }

    func test_noBeatDropsBpmButKeepsKey() async {
        // Deterministic noise: no rhythmic structure → BPM confidence too low → BPM dropped.
        var seed: UInt64 = 0xBEEF
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max) }
        let noise = (0..<Int(22050 * 5)).map { _ in rnd() }
        let p = PreviewDSPProvider(resolver: FakeResolver(match: match(preview: "https://x/p.m4a")),
                                   loader: FakeLoader(samples: noise))
        let f = await p.lookup(artist: "A", title: "T", id: "id")
        XCTAssertEqual(f.state, .found)
        XCTAssertNotNil(f.camelot)
        XCTAssertNil(f.bpm)                              // low-confidence BPM not trusted
    }
}
