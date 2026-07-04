import Foundation

/// A small semantic-version type for the update checker: parses `v1.2.3`,
/// compares numerically (so 1.10 > 1.9), treats missing components as zero
/// (1.2 == 1.2.0), and sorts pre-releases below their final version.
struct SemanticVersion: Equatable, Comparable {
    let components: [Int]
    let prerelease: [String]

    init?(_ raw: String) {
        var string = raw.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("v") || string.hasPrefix("V") {
            string = String(string.dropFirst())
        }
        // Drop build metadata (+…) entirely.
        if let plus = string.firstIndex(of: "+") {
            string = String(string[..<plus])
        }
        let coreAndPre = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = coreAndPre.first, !core.isEmpty else { return nil }

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        var nums: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            nums.append(value)
        }
        guard !nums.isEmpty else { return nil }
        components = nums
        prerelease = coreAndPre.count > 1
            ? coreAndPre[1].split(separator: ".").map(String.init)
            : []
    }

    private static func padded(_ a: [Int], _ b: [Int]) -> ([Int], [Int]) {
        let n = max(a.count, b.count)
        return (a + Array(repeating: 0, count: n - a.count),
                b + Array(repeating: 0, count: n - b.count))
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let (a, b) = padded(lhs.components, rhs.components)
        return a == b && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let (a, b) = padded(lhs.components, rhs.components)
        if a != b { return a.lexicographicallyPrecedes(b) }
        // Equal core: a version with a pre-release is lower than one without.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false   // lhs final > rhs pre-release
        case (false, true): return true    // lhs pre-release < rhs final
        case (false, false): return comparePrerelease(lhs.prerelease, rhs.prerelease)
        }
    }

    private static func comparePrerelease(_ a: [String], _ b: [String]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            switch (Int(x), Int(y)) {
            case let (xi?, yi?): return xi < yi
            case (_?, nil): return true       // numeric identifiers rank below alphanumeric
            case (nil, _?): return false
            default: return x < y
            }
        }
        return a.count < b.count              // a shorter prefix is older
    }
}
