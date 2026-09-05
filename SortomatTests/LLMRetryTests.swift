import XCTest
@testable import Sortomat

/// Serves scripted HTTP responses to `LLMClient` so the retry taxonomy can be
/// pinned without a network.
///
/// The scripted queue and the request counter are shared mutable statics, so
/// only one test may drive this at a time. XCTest runs the methods of a class
/// serially and `LLMRetryTests` is the only user, which is what keeps that
/// true — enabling parallel execution across classes would need a per-test
/// instance instead.
final class StubURLProtocol: URLProtocol {
    static var queue: [(status: Int, body: String)] = []
    static var requestCount = 0

    static func reset(_ responses: [(Int, String)]) {
        queue = responses.map { (status: $0.0, body: $0.1) }
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let next = Self.queue.isEmpty ? (status: 500, body: "") : Self.queue.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: next.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LLMRetryTests: XCTestCase {
    private let goodBody = #"{"choices":[{"message":{"content":"{\"action\":\"move\",\"folder\":\"A\",\"filename\":\"x.pdf\"}"}}],"usage":{"prompt_tokens":5,"completion_tokens":2}}"#

    private func makeClient() throws -> LLMClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        var client = LLMClient(apiKey: "k", model: "m", baseURL: try XCTUnwrap(URL(string: "https://llm.test")))
        client.session = URLSession(configuration: configuration)
        client.retryBaseDelay = 0
        return client
    }

    private func classify(_ client: LLMClient) async throws -> ClassificationResult {
        try await client.classify(rulePrompt: "sort", taxonomy: [], fileDescription: "File: x")
    }

    func testClientErrorSurfacesWithoutRetry() async throws {
        StubURLProtocol.reset([(400, #"{"error":"bad request"}"#)])
        do {
            _ = try await classify(try makeClient())
            XCTFail("expected an error")
        } catch let LLMError.http(status, _) {
            XCTAssertEqual(status, 400)
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "a 400 fails identically every time; never retried")
    }

    func testRateLimitIsRetriedUntilItSucceeds() async throws {
        StubURLProtocol.reset([(429, ""), (429, ""), (200, goodBody)])
        let result = try await classify(try makeClient())
        XCTAssertEqual(result.classification.folder, "A")
        XCTAssertEqual(result.usage.input, 5)
        XCTAssertEqual(StubURLProtocol.requestCount, 3)
    }

    func testNonJSONSuccessBodyIsTerminal() async throws {
        // A captive portal or proxy answering 200 with HTML used to be
        // retried four times with ~12 s of sleeps per file.
        StubURLProtocol.reset([(200, "<html><body>Sign in to the network</body></html>")])
        do {
            _ = try await classify(try makeClient())
            XCTFail("expected an error")
        } catch let LLMError.badResponse(detail) {
            XCTAssertTrue(detail.contains("Sign in"), "the body is the evidence: \(detail)")
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testServerErrorsGiveUpAfterFourAttempts() async throws {
        StubURLProtocol.reset([(503, ""), (503, ""), (503, ""), (503, "")])
        do {
            _ = try await classify(try makeClient())
            XCTFail("expected an error")
        } catch let LLMError.http(status, _) {
            XCTAssertEqual(status, 503)
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 4)
    }
}
