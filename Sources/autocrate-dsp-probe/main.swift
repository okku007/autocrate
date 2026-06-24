// Phase 0 GATE harness: run the on-device DSP estimators (AudioDecoder + KeyEstimator +
// TempoEstimator) against real Apple preview clips and compare to known BPM/key — the go/no-go
// for migrating off GetSongBPM.
//
//   CLIPS=/path/to/clips swift run autocrate-dsp-probe
//
// Expects <name>.m4a files in the clip dir for each truth entry below.

import Foundation
import AutocrateCore

let clipsDir = ProcessInfo.processInfo.environment["CLIPS"]
    ?? CommandLine.arguments.dropFirst().first
    ?? FileManager.default.currentDirectoryPath + "/clips"

struct Truth { let name: String; let bpm: Int; let camelot: String }
let truths = [
    Truth(name: "strobe",          bpm: 128, camelot: "1A"),
    Truth(name: "hotelcalifornia", bpm: 75,  camelot: "10B"),
    Truth(name: "bangarang",       bpm: 110, camelot: "?"),
]

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
func f(_ d: Double, _ p: Int = 1) -> String { String(format: "%.\(p)f", d) }

print("clips: \(clipsDir)\n")
for t in truths {
    let url = URL(fileURLWithPath: "\(clipsDir)/\(t.name).m4a")
    do {
        let samples = try await AudioDecoder.monoSamples(url: url, sampleRate: 22050)
        let tempo = TempoEstimator.estimate(samples, sampleRate: 22050, band: 70...180)
        let key = KeyEstimator.estimate(samples, sampleRate: 22050)
        print("\(pad(t.name,16)) BPM \(pad(f(tempo.bpm),6)) (conf \(f(tempo.confidence,2)))   "
            + "key \(pad(key.camelot.description,4)) (conf \(f(key.confidence,2)))   "
            + "truth: \(t.bpm) / \(t.camelot)")
    } catch {
        print("\(pad(t.name,16)) decode error: \(error)")
    }
}
