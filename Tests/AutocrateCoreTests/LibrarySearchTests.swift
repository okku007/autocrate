import XCTest
@testable import AutocrateCore

final class LibrarySearchTests: XCTestCase {
    private func t(_ id: String, _ title: String, _ artist: String) -> Track {
        Track(id: id, title: title, artist: artist, genre: nil, bpm: nil, camelot: nil)
    }

    func test_emptyQueryReturnsAllInOrder() {
        let tracks = [t("1","A","x"), t("2","B","y")]
        XCTAssertEqual(LibrarySearch.filter(query: "  ", tracks: tracks).map(\.id), ["1","2"])
    }
    func test_matchesTitleCaseInsensitive() {
        let tracks = [t("1","Brightest Lights","Lane 8"), t("2","Atlas","x")]
        XCTAssertEqual(LibrarySearch.filter(query: "BRIGHT", tracks: tracks).map(\.id), ["1"])
    }
    func test_matchesArtist() {
        let tracks = [t("1","Brightest Lights","Lane 8"), t("2","Atlas","Other")]
        XCTAssertEqual(LibrarySearch.filter(query: "lane", tracks: tracks).map(\.id), ["1"])
    }

    func test_classifyThreeWays() {
        let tracks = [t("s","S","x"), t("m","M","y"), t("n","N","z")]
        let out = LibrarySearch.classify(tracks: tracks, analyzedIDs: ["s"], missedIDs: ["m"])
        XCTAssertEqual(out.map(\.category), [.scanned, .missed, .notAnalyzed])
        XCTAssertEqual(out.map(\.isAnalyzed), [true, false, false])
    }
    func test_notAnalyzedExcludesScannedAndMissed() {
        let tracks = [t("s","S","x"), t("m","M","y"), t("n","N","z")]
        XCTAssertEqual(
            LibrarySearch.notAnalyzed(tracks: tracks, analyzedIDs: ["s"], missedIDs: ["m"]).map(\.id),
            ["n"])
    }
    func test_classifyScannedWinsIfIdInBothSets() {
        let tracks = [t("s","S","x")]
        let out = LibrarySearch.classify(tracks: tracks, analyzedIDs: ["s"], missedIDs: ["s"])
        XCTAssertEqual(out[0].category, .scanned)
    }
    func test_classifyIdAbsentFromLibraryIsIgnored() {
        let tracks = [t("a","A","x")]
        let out = LibrarySearch.classify(tracks: tracks, analyzedIDs: ["a","ghost"], missedIDs: [])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].category, .scanned)
    }

    func test_dedupeByIDKeepsFirstOccurrenceInOrder() {
        // Same normalized id ("a") appears twice — a duplicate library row. Collapse to the first.
        let tracks = [t("a","First","x"), t("b","B","y"), t("a","Second","z")]
        let out = LibrarySearch.dedupeByID(tracks)
        XCTAssertEqual(out.map(\.id), ["a", "b"])
        XCTAssertEqual(out.first?.title, "First")
    }
}
