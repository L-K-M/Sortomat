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

    // MARK: - Request payload

    func testPayloadCapsCompletionTokens() {
        let payload = LLMClient.payload(model: "m", rulePrompt: "sort",
                                        taxonomy: [], fileDescription: "File: x")
        XCTAssertEqual(payload["max_tokens"] as? Int, LLMClient.maxCompletionTokens,
                       "an uncapped answer bills unbounded output tokens per file")
        XCTAssertEqual(payload["temperature"] as? Int, 0)
    }

    func testPayloadInjectsTaxonomyIntoTheUserMessage() throws {
        let payload = LLMClient.payload(model: "m", rulePrompt: "sort",
                                        taxonomy: ["Fantasy", "Krimi"],
                                        fileDescription: "File: x")
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(user.contains("Fantasy, Krimi"))

        let without = LLMClient.payload(model: "m", rulePrompt: "sort",
                                        taxonomy: [], fileDescription: "File: x")
        let bareUser = try XCTUnwrap((without["messages"] as? [[String: Any]])?.last?["content"] as? String)
        XCTAssertFalse(bareUser.contains("MUST be exactly one of"))
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


    func testReasoningModelsGetTheParametersTheyAccept() throws {
        // o-series and gpt-5* reject "max_tokens" and any set temperature with
        // a non-retryable 400, so every classification would fail.
        for model in ["o3-mini", "o1", "gpt-5.1", "openai/o4-mini"] {
            let payload = LLMClient.payload(model: model, rulePrompt: "sort",
                                            taxonomy: [], fileDescription: "File: x")
            XCTAssertEqual(payload["max_completion_tokens"] as? Int, LLMClient.maxCompletionTokens,
                           "\(model) must use the parameter it accepts")
            XCTAssertNil(payload["max_tokens"], "\(model) rejects the legacy name")
            XCTAssertNil(payload["temperature"], "\(model) rejects a set temperature")
        }
    }

    func testClassicModelsKeepTheClassicParameters() {
        for model in ["mistral-small-latest", "gpt-4o-mini", "llama3.2", "qwen2.5:7b"] {
            let payload = LLMClient.payload(model: model, rulePrompt: "sort",
                                            taxonomy: [], fileDescription: "File: x")
            XCTAssertEqual(payload["max_tokens"] as? Int, LLMClient.maxCompletionTokens)
            XCTAssertEqual(payload["temperature"] as? Int, 0)
            XCTAssertNil(payload["max_completion_tokens"])
        }
    }
}
