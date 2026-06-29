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

    func test_annotateSplitsAnalyzed() {
        let tracks = [t("a","A","x"), t("b","B","y")]
        let out = LibrarySearch.annotate(tracks: tracks, analyzedIDs: ["a"])
        XCTAssertEqual(out.map(\.isAnalyzed), [true, false])
    }
    func test_newSongsAreTheUnanalyzed() {
        let tracks = [t("a","A","x"), t("b","B","y")]
        XCTAssertEqual(LibrarySearch.newSongs(tracks: tracks, analyzedIDs: ["a"]).map(\.id), ["b"])
    }
    func test_analyzedIdAbsentFromLibraryIsIgnored() {
        let tracks = [t("a","A","x")]
        let out = LibrarySearch.annotate(tracks: tracks, analyzedIDs: ["a","ghost"])
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isAnalyzed)
    }
}
