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
}
