import XCTest
@testable import Sortomat

final class LLMClientTests: XCTestCase {
    // MARK: - Endpoint building

    func testEndpointAppendsV1ForBareHost() {
        let url = LLMClient.endpoint(for: URL(string: "https://api.mistral.ai")!)
        XCTAssertEqual(url.absoluteString, "https://api.mistral.ai/v1/chat/completions")
    }

    func testEndpointDoesNotDoubleV1() {
        let url = LLMClient.endpoint(for: URL(string: "http://localhost:11434/v1")!)
        XCTAssertEqual(url.absoluteString, "http://localhost:11434/v1/chat/completions")
    }

    func testEndpointToleratesTrailingSlash() {
        XCTAssertEqual(
            LLMClient.endpoint(for: URL(string: "http://localhost:1234/v1/")!).path,
            "/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMClient.endpoint(for: URL(string: "https://api.mistral.ai/")!).path,
            "/v1/chat/completions"
        )
    }

    func testEndpointKeepsCustomPrefixes() {
        let url = LLMClient.endpoint(for: URL(string: "https://gateway.example.com/proxy/v1")!)
        XCTAssertEqual(url.path, "/proxy/v1/chat/completions")
    }

    // MARK: - Response parsing

    private func response(content: String, usage: String = "") -> Data {
        Data("""
        {"choices":[{"message":{"content":\(content)}}]\(usage)}
        """.utf8)
    }

    func testParsePlainJSONContent() throws {
        let data = response(
            content: #""{\"action\":\"move\",\"folder\":\"A\",\"filename\":\"b.txt\"}""#,
            usage: #","usage":{"prompt_tokens":12,"completion_tokens":3}"#
        )
        let result = try LLMClient.parse(data)
        XCTAssertEqual(result.classification.folder, "A")
        XCTAssertEqual(result.usage.input, 12)
        XCTAssertEqual(result.usage.output, 3)
    }

    func testParseStripsMarkdownFence() throws {
        let data = response(
            content: #""```json\n{\"action\":\"skip\",\"reason\":\"n/a\"}\n```""#
        )
        let result = try LLMClient.parse(data)
        XCTAssertEqual(result.classification.action, "skip")
    }

    func testParseMissingContentThrows() {
        let data = Data(#"{"choices":[]}"#.utf8)
        XCTAssertThrowsError(try LLMClient.parse(data)) { error in
            guard case LLMError.badResponse = error else {
                return XCTFail("expected badResponse, got \(error)")
            }
        }
    }

    func testParseNonJSONContentThrows() {
        let data = response(content: #""I would put this file in the Invoices folder.""#)
        XCTAssertThrowsError(try LLMClient.parse(data))
    }
}
