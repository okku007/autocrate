import XCTest
@testable import AutocrateCore

final class ITunesResolverTests: XCTestCase {
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
    func test_parsesPreviewUrl() {
        let json = """
        {"results":[{"trackName":"Strobe","artistName":"deadmau5","trackViewUrl":"https://music.apple.com/x","previewUrl":"https://audio-ssl.itunes.apple.com/x.m4a"}]}
        """.data(using: .utf8)!
        XCTAssertEqual(iTunesResolver.parse(json)?.previewUrl,
                       URL(string: "https://audio-ssl.itunes.apple.com/x.m4a"))
    }
}
