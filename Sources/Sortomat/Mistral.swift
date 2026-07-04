import Foundation

struct Classification: Decodable {
    let action: String
    let relativePath: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case action
        case relativePath = "relative_path"
        case reason
    }
}

enum MistralError: LocalizedError {
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Mistral API HTTP \(code): \(String(body.prefix(200)))"
        case .badResponse(let detail):
            return "Unerwartete API-Antwort: \(detail)"
        }
    }
}

struct MistralClient {
    let apiKey: String
    let model: String
    let baseURL: URL

    static let systemPrompt = """
    Du bist ein Datei-Sortier-Assistent. Du erhältst eine vom Benutzer definierte \
    Sortierregel und Informationen zu einer Datei (Name, Metadaten, Textauszug).

    Antworte ausschliesslich mit einem JSON-Objekt:
    {
      "action": "move" oder "skip",
      "relative_path": "Zielpfad/relativ/zum/Zielordner/Dateiname.ext",
      "reason": "kurze Begründung"
    }

    Regeln:
    - "relative_path": Pfad relativ zum Zielordner der Regel, "/" als Trenner,
      inklusive Dateiname. Die originale Dateiendung MUSS erhalten bleiben.
    - Baue die Ordnerstruktur exakt so, wie es die Sortierregel verlangt.
    - Keine absoluten Pfade, keine ".."-Segmente.
    - Verwende "skip", wenn die Regel auf diese Datei nicht zutrifft oder du dir
      sehr unsicher bist; "relative_path" darf dann fehlen.
    """

    func classify(rulePrompt: String, fileDescription: String) async throws -> Classification {
        let userPrompt = "Sortierregel des Benutzers:\n\(rulePrompt)\n\n\(fileDescription)"
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
        ]

        var request = URLRequest(
            url: baseURL.appendingPathComponent("v1/chat/completions")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 90

        var lastError: Error = MistralError.badResponse("keine Antwort")
        for attempt in 0..<4 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    return try Self.parse(data)
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                lastError = MistralError.http(status, body)
                // 401 etc. won't get better by retrying.
                guard [429, 500, 502, 503, 504].contains(status) else { throw lastError }
            } catch let error as MistralError {
                lastError = error
                if case .http = error {} else { throw error }
            } catch {
                lastError = error // network hiccup: retry
            }
            if attempt < 3 {
                try await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (attempt + 1)))
            }
        }
        throw lastError
    }

    private static func parse(_ data: Data) throws -> Classification {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            var content = message["content"] as? String
        else {
            throw MistralError.badResponse("choices/message/content fehlt")
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```") {
            content = content
                .replacingOccurrences(
                    of: "^```(json)?\\s*|\\s*```$", with: "",
                    options: .regularExpression
                )
        }
        do {
            return try JSONDecoder().decode(Classification.self, from: Data(content.utf8))
        } catch {
            throw MistralError.badResponse(String(content.prefix(200)))
        }
    }
}
