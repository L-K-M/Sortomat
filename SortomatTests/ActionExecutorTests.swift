import XCTest
@testable import Sortomat

/// Tag arithmetic is pure on purpose: what a rule does to a file's tags can be
/// pinned without a file system, and the one part that touches the disk is a
/// single `setResourceValues`.
final class ActionExecutorTests: XCTestCase {
    private func effect(_ type: ActionType, _ values: [String]) -> SideEffect {
        SideEffect(type: type, values: values)
    }

    func testAddingTagsKeepsWhatIsThereAndAppendsWhatIsNot() {
        let result = ActionExecutor.resolve(["Steuern"],
                                            applying: effect(.addTags, ["Rechnung", "2026"]))
        XCTAssertEqual(result, ["Steuern", "Rechnung", "2026"])
    }

    func testATagIsNotAddedTwiceInADifferentCase() {
        // Finder's own list is case-insensitive: a file cannot hold both
        // spellings, so adding the second must not duplicate the first.
        let result = ActionExecutor.resolve(["Steuern"], applying: effect(.addTags, ["steuern"]))
        XCTAssertEqual(result, ["Steuern"], "the spelling already on the file wins")
    }

    func testBlankTagsAreIgnoredRatherThanWritten() {
        // The value comes from a rendered template: a token that resolved to
        // nothing leaves an empty string, and an empty Finder tag is not a tag.
        let result = ActionExecutor.resolve([], applying: effect(.addTags, ["", "  ", "Rechnung"]))
        XCTAssertEqual(result, ["Rechnung"])
    }

    func testTagValuesAreTrimmed() {
        let result = ActionExecutor.resolve([], applying: effect(.addTags, ["  Rechnung  "]))
        XCTAssertEqual(result, ["Rechnung"])
    }

    func testRemovingTagsIsCaseInsensitiveAndLeavesTheRest() {
        let result = ActionExecutor.resolve(["Steuern", "Rechnung", "2026"],
                                            applying: effect(.removeTags, ["rechnung"]))
        XCTAssertEqual(result, ["Steuern", "2026"])
    }

    func testRemovingATagTheFileDoesNotHaveChangesNothing() {
        let existing = ["Steuern"]
        XCTAssertEqual(ActionExecutor.resolve(existing, applying: effect(.removeTags, ["Urlaub"])),
                       existing)
    }

    func testAnEffectThatIsNotAboutTagsLeavesThemAlone() {
        let existing = ["Steuern"]
        XCTAssertEqual(ActionExecutor.resolve(existing, applying: effect(.notify, ["done"])),
                       existing)
    }

    func testTagsAreWrittenToARealFileAndReadBack() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sortomat-tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("invoice.pdf")
        try Data("x".utf8).write(to: file)

        let performed = ActionExecutor.apply([effect(.addTags, ["Rechnung"])], to: file)
        XCTAssertEqual(performed, [.addTags])
        let after = try file.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        XCTAssertEqual(after, ["Rechnung"])

        XCTAssertEqual(ActionExecutor.apply([effect(.removeTags, ["rechnung"])], to: file),
                       [.removeTags])
        let empty = try file.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        XCTAssertTrue(empty.isEmpty, "got: \(empty)")
    }

    func testUnsupportedEffectsAreSkippedRatherThanPretended() {
        // The validator reads the same set, so what the editor promises and
        // what the executor does cannot drift.
        XCTAssertFalse(ActionExecutor.supported.contains(.setComment))
        XCTAssertFalse(ActionExecutor.supported.contains(.reveal))
        let performed = ActionExecutor.apply([effect(.setComment, ["hello"]),
                                              effect(.reveal, [])],
                                             to: FileManager.default.temporaryDirectory)
        XCTAssertTrue(performed.isEmpty)
    }
}
