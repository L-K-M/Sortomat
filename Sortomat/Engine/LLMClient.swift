import Foundation

struct TokenUsage: Equatable {
    var input: Int = 0
    var output: Int = 0

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(input: lhs.input + rhs.input, output: lhs.output + rhs.output)
    }
}

struct ClassificationResult {
    let classification: Classification
    let usage: TokenUsage
}

enum LLMError: LocalizedError {
    case http(Int, String)
    case badResponse(String)
    case badBaseURL

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return L10n.t("error.http", code, String(body.prefix(200)))
        case .badResponse(let detail): return L10n.t("error.badResponse", detail)
        case .badBaseURL: return L10n.t("error.badApiBase")
        }
    }
}

/// A provider-agnostic client for any OpenAI-compatible `chat/completions`
/// endpoint: Mistral, OpenAI, or a local server (Ollama, LM Studio). The base
/// URL, model and whether a key is required all come from config, so switching
/// to a local/free model is just settings (PLAN Phase 5).
struct LLMClient {
    let apiKey: String
    let model: String
    let baseURL: URL
    var session: URLSession = .shared
    /// Base of the linear back-off between retries (2 s, 4 s, 6 s). Tests set
    /// it to zero.
    var retryBaseDelay: TimeInterval = 2

    static let systemPrompt = """
    You are a file-sorting assistant. You receive a user-defined sorting rule and \
    information about a single file (name, metadata, and possibly a content excerpt).

    Respond with ONLY a JSON object:
    {
      "action": "move" or "skip",
      "folder": "sub/folder/relative/to/the/target",
      "filename": "Name.ext",
      "confidence": 0.0 to 1.0,
      "reason": "one short sentence"
    }

    Rules:
    - "folder" is relative to the rule's target folder, using "/" as the separator.
      Build the folder structure exactly as the sorting rule asks. It may be empty
      to place the file directly in the target.
    - "filename" keeps the file's original extension.
    - No absolute paths, no ".." segments.
    - Use "action": "skip" when the rule does not apply to this file or you are very
      unsure; folder/filename may then be omitted.
    - "confidence" reflects how sure you are of the destination.
    - If the rule restricts the top-level folder to an allowed set, you MUST choose
      exactly one of those; never invent a folder outside the set.
    """

    /// Upper bound on the answer. The expected response is a five-field JSON
    /// object; without a cap, a rambling model — or a file whose content
    /// steers it into rambling — bills unbounded output tokens per file.
    static let maxCompletionTokens = 700

    /// The chat/completions request body, extracted so tests can pin its shape.
    static func payload(
        model: String, rulePrompt: String, taxonomy: [String], fileDescription: String
    ) -> [String: Any] {
        var instruction = "User's sorting rule:\n\(rulePrompt)"
        if !taxonomy.isEmpty {
            instruction += "\n\nThe top-level folder MUST be exactly one of: "
                + taxonomy.joined(separator: ", ")
        }
        let userPrompt = "\(instruction)\n\n\(fileDescription)"
        return [
            "model": model,
            "temperature": 0,
            "max_tokens": maxCompletionTokens,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
        ]
    }

    func classify(
        rulePrompt: String,
        taxonomy: [String],
        fileDescription: String
    ) async throws -> ClassificationResult {
        let payload = Self.payload(
            model: model, rulePrompt: rulePrompt,
            taxonomy: taxonomy, fileDescription: fileDescription
        )

        var request = URLRequest(url: Self.endpoint(for: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 90

        var lastError: Error = LLMError.badResponse("no response")
        for attempt in 0..<4 {
            let retryable: Bool
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    return try Self.parse(data) // parse failures are terminal, not retried
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                lastError = LLMError.http(status, body)
                // Retry only genuinely transient statuses; a 400/401/403 will
                // fail identically every time and must surface immediately.
                retryable = [429, 500, 502, 503, 504].contains(status)
            } catch let error as LLMError {
                throw error // bad response body — retrying won't change it
            } catch {
                lastError = error // network hiccup: retry
                retryable = true
            }
            guard retryable else { throw lastError }
            if attempt < 3, retryBaseDelay > 0 {
                try await Task.sleep(nanoseconds: UInt64(retryBaseDelay * Double(attempt + 1) * 1_000_000_000))
            }
        }
        throw lastError
    }

    /// The `chat/completions` endpoint for a configured base URL. Tolerates the
    /// two conventions in the wild: a bare host (`https://api.mistral.ai`) and a
    /// base that already ends in `/v1` (`http://localhost:11434/v1`, the form
    /// Ollama/LM Studio docs use) — without this, the latter became `/v1/v1/…`.
    static func endpoint(for base: URL) -> URL {
        var path = base.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/v1") {
            return base.appendingPathComponent("chat/completions")
        }
        return base.appendingPathComponent("v1/chat/completions")
    }

    static func parse(_ data: Data) throws -> ClassificationResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            // Not JSON at all — a captive portal, a proxy's HTML error page, a
            // wrong base URL answering 200 with a web page. Terminal, with the
            // body as evidence; the generic retry path must never see it.
            throw LLMError.badResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard
            let root = object as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            var content = message["content"] as? String
        else {
            throw LLMError.badResponse("choices/message/content missing")
        }
        var usage = TokenUsage()
        if let u = root["usage"] as? [String: Any] {
            usage.input = (u["prompt_tokens"] as? Int) ?? 0
            usage.output = (u["completion_tokens"] as? Int) ?? 0
        }

        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```") {
            content = content.replacingOccurrences(
                of: "^```(json)?\\s*|\\s*```$", with: "", options: .regularExpression
            )
        }
        do {
            let classification = try JSONDecoder().decode(Classification.self, from: Data(content.utf8))
            return ClassificationResult(classification: classification, usage: usage)
        } catch {
            throw LLMError.badResponse(String(content.prefix(200)))
        }
    }
}
