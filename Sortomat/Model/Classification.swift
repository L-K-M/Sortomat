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
        action = Self.decodeAction(c)
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

    /// Only an affirmative action moves a file. Anything unrecognized —
    /// "ignore", "none", "delete", hallucinated verbs — is treated as a skip:
    /// for a tool that moves files, the safe default for "I don't understand
    /// the answer" is to do nothing. (A missing action still decodes as
    /// "move", since some models omit it while supplying a path.)
    var isMove: Bool {
        ["move", "copy", "file", "sort", "rename"].contains(action)
    }

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

    /// The intended top-level folder (for taxonomy checks): the first path
    /// segment, ignoring a leading `.`.
    func topFolder() -> String? {
        if let f = folder?.trimmingCharacters(in: .whitespaces), !f.isEmpty {
            return f.split(separator: "/").map(String.init).first { $0 != "." }
        }
        return resolvedRelativePath().flatMap(Self.topFolder(ofRelativePath:))
    }

    /// The first directory segment of a relative path (nil when the path is a
    /// bare filename), ignoring `.` segments. Taxonomy is enforced against the
    /// path that will actually be applied, so a contradictory answer —
    /// `folder` inside the taxonomy, `relative_path` outside it — can't slip
    /// past the check.
    static func topFolder(ofRelativePath path: String) -> String? {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .dropLast()   // drop the filename
            .first { $0 != "." }
    }

    /// Strings are the contract; a boolean or number is read for its *sign*
    /// (`false`/`0` → skip, `true`/`1` → move); anything else that is present
    /// but unintelligible (`null`, an object) is a skip — the safe direction
    /// for a tool that moves files. Only a genuinely *absent* key means move,
    /// because some models omit it while supplying a path.
    private static func decodeAction(_ c: KeyedDecodingContainer<CodingKeys>) -> String {
        if let s = try? c.decode(String.self, forKey: .action) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if let b = try? c.decode(Bool.self, forKey: .action) { return b ? "move" : "skip" }
        if let n = try? c.decode(Int.self, forKey: .action) { return n != 0 ? "move" : "skip" }
        return c.contains(.action) ? "skip" : "move"
    }

    private static func decodeConfidence(_ c: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: .confidence) {
            return normalizeConfidence(d)
        }
        if let s = try? c.decodeIfPresent(String.self, forKey: .confidence) {
            return parseConfidence(s)
        }
        return nil
    }

    /// `"85%"`, `"85 %"`, `"0,85"` (decimal comma), `"high"` — models answer
    /// in every shape. Unparseable text yields nil, which the quarantine
    /// threshold treats as *low*, not as trusted.
    static func parseConfidence(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(cleaned) { return normalizeConfidence(d) }
        switch cleaned.lowercased() {
        case "very high", "high", "certain", "sure": return 0.9
        case "medium", "moderate", "likely": return 0.6
        case "low", "very low", "unsure", "uncertain": return 0.3
        default: return nil
        }
    }

    /// Models sometimes answer in percent (`85` or `"85%"`) instead of 0…1.
    /// Without normalizing the *numeric* form too, `85 < threshold` is never
    /// true and the low-confidence quarantine is silently defeated.
    ///
    /// Nil for anything that isn't a finite number. `Double("nan")` parses, and
    /// NaN survives both the scaling and the clamp (`min`/`max` return the
    /// other operand when a comparison with NaN is false) — after which every
    /// `confidence < threshold` test is false too, and a garbage answer reads
    /// as full confidence. Unparseable text already means "low"; so does this.
    private static func normalizeConfidence(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        let scaled = value > 1 ? value / 100 : value
        return min(max(scaled, 0), 1)
    }
}
