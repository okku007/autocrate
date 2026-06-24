/// Key-dominant hybrid `FeatureProvider`. Camelot always comes from on-device DSP (full catalog
/// coverage); BPM comes from DSP when it's confident, else is backfilled from a network fallback
/// (GetSongBPM). The DSP Camelot is never overwritten by the fallback.
public struct HybridFeatureProvider: FeatureProvider {
    let dsp: FeatureProvider
    let bpmFallback: FeatureProvider

    public init(dsp: FeatureProvider, bpmFallback: FeatureProvider) {
        self.dsp = dsp
        self.bpmFallback = bpmFallback
    }

    public func lookup(artist: String, title: String, id: String) async -> CachedFeature {
        let f = await dsp.lookup(artist: artist, title: title, id: id)
        guard f.state == .found, f.bpm == nil else { return f }

        let api = await bpmFallback.lookup(artist: artist, title: title, id: id)
        guard let apiBpm = api.bpm else { return f }

        return CachedFeature(id: f.id, title: f.title, artist: f.artist, bpm: apiBpm,
                             camelot: f.camelot, musicalKey: f.musicalKey,
                             source: "dsp+api", state: f.state, fetchedAt: f.fetchedAt)
    }
}
