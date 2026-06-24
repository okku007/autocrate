import XCTest
@testable import AutocrateCore

final class ITunesResolverTests: XCTestCase {
    func test_parsesMatchingResult() {
        let json = """
        {"resultCount":1,"results":[{"trackName":"Strobe","artistName":"deadmau5","trackViewUrl":"https://music.apple.com/x"}]}
        """.data(using: .utf8)!
        let match = iTunesResolver.parse(json, artist: "deadmau5", title: "Strobe")
        XCTAssertEqual(match?.title, "Strobe")
        XCTAssertEqual(match?.artist, "deadmau5")
        XCTAssertEqual(match?.appleMusicURL.absoluteString, "https://music.apple.com/x")
    }
    func test_emptyResultsReturnsNil() {
        let json = #"{"resultCount":0,"results":[]}"#.data(using: .utf8)!
        XCTAssertNil(iTunesResolver.parse(json, artist: "deadmau5", title: "Strobe"))
    }
    func test_parsesPreviewUrl() {
        let json = """
        {"results":[{"trackName":"Strobe","artistName":"deadmau5","trackViewUrl":"https://music.apple.com/x","previewUrl":"https://audio-ssl.itunes.apple.com/x.m4a"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(iTunesResolver.parse(json, artist: "deadmau5", title: "Strobe")?.previewUrl,
                       URL(string: "https://audio-ssl.itunes.apple.com/x.m4a"))
    }
    func test_picksResultMatchingTitleNotArtistTopHit() {
        // The collab bug: iTunes returns the artist's top song first; the real track is further down.
        let json = """
        {"results":[
          {"trackName":"Brightest Lights","artistName":"Lane 8","trackViewUrl":"https://music.apple.com/a","previewUrl":"https://x/a.m4a"},
          {"trackName":"The Deep","artistName":"Lane 8 & Art School Girlfriend","trackViewUrl":"https://music.apple.com/b","previewUrl":"https://x/b.m4a"}
        ]}
        """.data(using: .utf8)!
        let match = iTunesResolver.parse(json, artist: "Lane 8 & Art School Girlfriend", title: "The Deep")
        XCTAssertEqual(match?.title, "The Deep")
        XCTAssertEqual(match?.previewUrl, URL(string: "https://x/b.m4a"))
    }
    func test_returnsNilWhenNoResultMatchesTitle() {
        // No real match present → miss, NOT the artist's unrelated top hit (which would be wrong data).
        let json = """
        {"results":[
          {"trackName":"Brightest Lights","artistName":"Lane 8","trackViewUrl":"https://music.apple.com/a","previewUrl":"https://x/a.m4a"}
        ]}
        """.data(using: .utf8)!
        XCTAssertNil(iTunesResolver.parse(json, artist: "Lane 8 & Kasablanca", title: "You"))
    }
    func test_titleMatchToleratesSuffix() {
        let json = """
        {"results":[{"trackName":"Strobe (Original Mix)","artistName":"deadmau5","trackViewUrl":"https://music.apple.com/x"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(iTunesResolver.parse(json, artist: "deadmau5", title: "Strobe")?.title, "Strobe (Original Mix)")
    }
}
