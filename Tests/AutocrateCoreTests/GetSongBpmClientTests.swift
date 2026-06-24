import XCTest
@testable import AutocrateCore

/// Stubs the network so we can feed GetSongBpmClient exact response bytes.
final class StubURLProtocol: URLProtocol {
    static var body = Data()
    static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GetSongBpmClientTests: XCTestCase {
    private func makeClient() -> GetSongBpmClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return GetSongBpmClient(apiKey: "test", session: URLSession(configuration: cfg))
    }

    /// A hit decodes the array form: bpm from `tempo`, Camelot from `open_key` (6m → 1A).
    func testLookupHitDecodes() async {
        StubURLProtocol.body = Data(#"{"search":[{"tempo":"128","key_of":"G♯m","open_key":"6m"}]}"#.utf8)
        let f = await makeClient().lookup(artist: "deadmau5", title: "Strobe", id: "id1")
        XCTAssertEqual(f.state, .found)
        XCTAssertEqual(f.bpm, 128)
        XCTAssertEqual(f.camelot, "1A")
    }

    /// No result comes back as `"search": {"error":"no result"}` (an OBJECT, not an array).
    /// This must decode to a clean miss — not throw "isn't in the correct format".
    func testLookupNoResultObjectShapeIsMiss() async {
        StubURLProtocol.body = Data(#"{"search":{"error":"no result"}}"#.utf8)
        let f = await makeClient().lookup(artist: "nobody", title: "nothing", id: "id2")
        XCTAssertEqual(f.state, .miss)
        XCTAssertNil(f.bpm)
        XCTAssertNil(f.camelot)
    }
}
