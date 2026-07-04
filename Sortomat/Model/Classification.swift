import Foundation

/// The model's answer for one file. `folder` + `filename` are preferred; a
/// combined `relativePath` is accepted as a fallback for older prompts.
struct Classification: Decodable, Equatable {
    let action: String
    let relativePath: String?
    let folder: String?
    let filename: String?
    let reason: String?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case action
        case relativePath = "relative_path"
        case folder
        case filename
        case reason
        case confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Be liberal: some models emit `"action": true/absent`; treat anything
        // that isn't an explicit skip, plus a present path, as a move.
        action = (try? c.decode(String.self, forKey: .action))?.lowercased() ?? "move"
        relativePath = try? c.decodeIfPresent(String.self, forKey: .relativePath)
        folder = try? c.decodeIfPresent(String.self, forKey: .folder)
        filename = try? c.decodeIfPresent(String.self, forKey: .filename)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        confidence = Self.decodeConfidence(c)
    }

    init(action: String, relativePath: String? = nil, folder: String? = nil,
         filename: String? = nil, reason: String? = nil, confidence: Double? = nil) {
        self.action = action
        self.relativePath = relativePath
        self.folder = folder
        self.filename = filename
        self.reason = reason
        self.confidence = confidence
    }

    var isMove: Bool { action != "skip" }

    /// The path relative to the target, assembled from whichever fields the model
    /// filled in. `nil` when there is nothing usable.
    func resolvedRelativePath() -> String? {
        if let rel = relativePath, !rel.trimmingCharacters(in: .whitespaces).isEmpty {
            return rel
        }
        let f = (folder ?? "").trimmingCharacters(in: .whitespaces)
        let n = (filename ?? "").trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return f.isEmpty ? n : "\(f)/\(n)"
    }

    /// The intended top-level folder (for taxonomy checks): the first path segment.
    func topFolder() -> String? {
        if let f = folder?.trimmingCharacters(in: .whitespaces), !f.isEmpty {
            return f.split(separator: "/").first.map(String.init)
        }
        return resolvedRelativePath()?
            .split(separator: "/", omittingEmptySubsequences: true)
            .dropLast()   // drop the filename
            .first
            .map(String.init)
    }

    private static func decodeConfidence(_ c: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: .confidence) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: .confidence) {
            return Double(s.replacingOccurrences(of: "%", with: ""))
                .map { $0 > 1 ? $0 / 100 : $0 }
        }
        return nil
    }
}
