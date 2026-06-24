import Foundation

/// Turns a preview-clip URL into mono samples for the DSP estimators. Injected as a fake in tests.
public protocol PreviewSampleLoader {
    func samples(for url: URL) async throws -> [Float]
}

/// Default loader: downloads the clip, writes it to a temp file (AVAudioFile needs a file URL),
/// and decodes it to mono at the target sample rate.
public struct NetworkPreviewLoader: PreviewSampleLoader {
    public var session: URLSession
    public var sampleRate: Double
    public init(session: URLSession = .shared, sampleRate: Double = 22050) {
        self.session = session
        self.sampleRate = sampleRate
    }
    public func samples(for url: URL) async throws -> [Float] {
        let (data, _) = try await session.data(from: url)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await AudioDecoder.monoSamples(url: tmp, sampleRate: sampleRate)
    }
}

/// `FeatureProvider` that derives Camelot key + BPM from Apple's free preview clip via on-device DSP.
/// Key is always taken from the chromagram (full catalog coverage); BPM is kept only when the tempo
/// estimator is confident, otherwise left nil so a hybrid caller can backfill it from an API.
public struct PreviewDSPProvider: FeatureProvider {
    let resolver: CatalogResolver
    let loader: PreviewSampleLoader
    let sampleRate: Double
    let band: ClosedRange<Double>
    let bpmConfidenceThreshold: Double

    public init(resolver: CatalogResolver = iTunesResolver(),
                loader: PreviewSampleLoader = NetworkPreviewLoader(),
                sampleRate: Double = 22050,
                band: ClosedRange<Double> = 70...180,
                bpmConfidenceThreshold: Double = 0.4) {
        self.resolver = resolver
        self.loader = loader
        self.sampleRate = sampleRate
        self.band = band
        self.bpmConfidenceThreshold = bpmConfidenceThreshold
    }

    public func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        let now = Int(Date().timeIntervalSince1970)
        func miss() -> CachedFeature {
            CachedFeature(id: id, title: title, artist: artist, bpm: nil, camelot: nil,
                          musicalKey: nil, source: "dsp", state: .miss, fetchedAt: now)
        }
        guard let match = await resolver.resolve(artist: artist, title: title),
              let preview = match.previewUrl,
              let samples = try? await loader.samples(for: preview),
              samples.count > 4096 else { return miss() }

        let key = KeyEstimator.estimate(samples, sampleRate: sampleRate)
        let tempo = TempoEstimator.estimate(samples, sampleRate: sampleRate, band: band)
        let bpm = tempo.confidence >= bpmConfidenceThreshold ? tempo.bpm.rounded() : nil
        return CachedFeature(id: id, title: title, artist: artist, bpm: bpm,
                             camelot: key.camelot.description, musicalKey: nil,
                             source: "dsp", state: .found, fetchedAt: now)
    }
}
