import XCTest
@testable import Sortomat

/// Document packages (Pages, Numbers, Keynote, RTFD, text bundles) are
/// folders on disk and used to be invisible to every rule.
final class PackageTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-package-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("watch"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("target"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    private func plantPackage(named name: String, ageSeconds: TimeInterval = 60) throws -> URL {
        let package = dir.appendingPathComponent("watch/\(name)")
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        let inner = package.appendingPathComponent("TXT.rtf")
        try "{\\rtf1 hello}".write(to: inner, atomically: true, encoding: .utf8)
        let old = Date(timeIntervalSinceNow: -ageSeconds)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: inner.path)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: package.path)
        return package
    }

    func testPackageCountsAsFileLikeButPlainFolderDoesNot() throws {
        let package = try plantPackage(named: "Draft.rtfd")
        XCTAssertTrue(Pipeline.isFileLike(package))
        XCTAssertFalse(Pipeline.isFileLike(dir.appendingPathComponent("watch/Letter.pages")),
                       "a nonexistent path is nothing")
        let plain = dir.appendingPathComponent("watch/Just a folder")
        try fm.createDirectory(at: plain, withIntermediateDirectories: true)
        XCTAssertFalse(Pipeline.isFileLike(plain))
        let pages = dir.appendingPathComponent("watch/Letter.pages")
        try fm.createDirectory(at: pages, withIntermediateDirectories: true)
        XCTAssertTrue(Pipeline.isFileLike(pages), "known document packages count even where their app isn't installed")
    }

    func testPackageIsSortedAsOneItem() async throws {
        let package = try plantPackage(named: "Draft.rtfd")
        let rule = Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path,
            recursive: true,
            preRules: [PreRule(match: .glob, pattern: "*.rtfd", action: .route, routePath: "Docs")]
        )
        let config = Config(rules: [rule], providerRequiresKey: false)
        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")))
        let result = await pipeline.scan(rule: rule, config: config, apiKey: "")

        XCTAssertTrue(result.entries.allSatisfy(\.ok), "\(result.entries.map(\.message))")
        XCTAssertFalse(fm.fileExists(atPath: package.path))
        let moved = dir.appendingPathComponent("target/Docs/Draft.rtfd")
        XCTAssertTrue(fm.fileExists(atPath: moved.appendingPathComponent("TXT.rtf").path),
                      "the package moves whole, innards included")
    }

    func testPackageSizeSignatureSeesGrowth() throws {
        let package = try plantPackage(named: "Growing.rtfd")
        let before = Pipeline.sizeSignature(of: package)
        try "more".write(to: package.appendingPathComponent("extra.txt"), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(before, Pipeline.sizeSignature(of: package))
    }

    /// A package has no prefix digest (it is a directory), so duplicate
    /// detection has to fall through to the whole-tree comparison — otherwise
    /// re-filing the same bundle piles up "Draft (2).rtfd", "Draft (3).rtfd".
    func testIdenticalPackagesAreRecognizedAsDuplicates() throws {
        let source = try plantPackage(named: "Draft.rtfd")
        let target = dir.appendingPathComponent("target")
        let existing = target.appendingPathComponent("Draft.rtfd")
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try "{\\rtf1 hello}".write(to: existing.appendingPathComponent("TXT.rtf"),
                                  atomically: true, encoding: .utf8)

        let outcome = try Mover.place(source: source, destination: existing, copy: false)
        if case .duplicate = outcome {} else { XCTFail("expected duplicate, got \(outcome)") }
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("Draft (2).rtfd").path))
    }

    func testDifferentPackagesUnderOneNameGetSuffixed() throws {
        let source = try plantPackage(named: "Draft.rtfd")
        let target = dir.appendingPathComponent("target")
        let existing = target.appendingPathComponent("Draft.rtfd")
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try "{\\rtf1 different}".write(to: existing.appendingPathComponent("TXT.rtf"),
                                       atomically: true, encoding: .utf8)

        let outcome = try Mover.place(source: source, destination: existing, copy: false)
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("Draft (2).rtfd").path),
                      "a different bundle must land beside the existing one, got \(outcome)")
    }

    /// Two bundles whose only difference is their folder layout used to hash
    /// the same empty string — and `copyVerifyDelete` then "verified" one
    /// against the other and deleted the original.
    func testTreeDigestDistinguishesPackagesThatHoldOnlyFolders() throws {
        let a = dir.appendingPathComponent("watch/A.rtfd")
        let b = dir.appendingPathComponent("watch/B.rtfd")
        try fm.createDirectory(at: a.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: b.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let digestA = try XCTUnwrap(Mover.treeDigest(of: a))
        XCTAssertNotEqual(digestA, Mover.treeDigest(of: b))
    }

    /// A `.framework` is mostly symlinks; hashing only the regular files made
    /// two differently linked bundles indistinguishable.
    func testTreeDigestCoversSymlinkTargets() throws {
        let a = dir.appendingPathComponent("watch/A.framework")
        let b = dir.appendingPathComponent("watch/B.framework")
        for bundle in [a, b] {
            try fm.createDirectory(at: bundle.appendingPathComponent("Versions/A"),
                                   withIntermediateDirectories: true)
            try "x".write(to: bundle.appendingPathComponent("Versions/A/lib"),
                          atomically: true, encoding: .utf8)
        }
        try fm.createSymbolicLink(atPath: a.appendingPathComponent("Versions/Current").path,
                                  withDestinationPath: "A")
        try fm.createSymbolicLink(atPath: b.appendingPathComponent("Versions/Current").path,
                                  withDestinationPath: "B")
        XCTAssertNotEqual(Mover.treeDigest(of: a), Mover.treeDigest(of: b))
    }

    func testTreeDigestCoversEveryFileInAPackage() throws {
        let a = try plantPackage(named: "A.rtfd")
        let b = try plantPackage(named: "B.rtfd")
        XCTAssertEqual(Mover.treeDigest(of: a), Mover.treeDigest(of: b), "identical bundles digest alike")
        try "changed".write(to: b.appendingPathComponent("TXT.rtf"), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(Mover.treeDigest(of: a), Mover.treeDigest(of: b))
    }
}
