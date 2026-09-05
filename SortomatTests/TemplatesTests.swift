import XCTest
@testable import Sortomat

final class TemplatesTests: XCTestCase {
    func testEbookTemplate() {
        let rule = RuleTemplate.ebooks.makeRule()
        XCTAssertEqual(rule.extensions, ["epub"])
        XCTAssertEqual(rule.taxonomy, RuleTemplate.ebookGenres)
        XCTAssertFalse(rule.prompt.isEmpty)
        XCTAssertFalse(rule.enabled)   // seeded disabled
        XCTAssertTrue(rule.dryRun)     // preview until the user opts in
    }

    func testEachTemplateProducesFreshID() {
        let a = RuleTemplate.ebooks.makeRule()
        let b = RuleTemplate.ebooks.makeRule()
        XCTAssertNotEqual(a.id, b.id)
    }

    func testAllTemplatesBuild() {
        for template in RuleTemplate.allCases {
            let rule = template.makeRule()
            XCTAssertFalse(rule.name.isEmpty)
        }
    }

    func testScreenshotsTemplateOnlySendsScreenshotsToTheModel() throws {
        let rule = RuleTemplate.screenshots.makeRule()
        // The last pre-rule must be a catch-all skip: without it, "route
        // screenshots to the model" was a no-op (the model is the fall-through
        // anyway) and every image in the folder was classified and paid for.
        XCTAssertEqual(rule.preRules.last?.action, .skip)
        XCTAssertEqual(rule.preRules.last?.pattern, "*")

        func decision(for name: String) -> DeterministicEngine.Decision {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? Data("x".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return DeterministicEngine.evaluate(rule: rule, file: url)
        }

        XCTAssertEqual(decision(for: "Screenshot 2026-07-05 at 10.00.00.png"), .useLLM)
        XCTAssertEqual(decision(for: "Bildschirmfoto 2026-07-05.png"), .useLLM,
                       "the German screenshot naming must reach the model too")
        if case .skip = decision(for: "IMG_1234.png") {} else {
            XCTFail("a non-screenshot image must be skipped, not classified")
        }
    }

    func testScreenshotsPromptDoesNotReferenceUnavailableImageContent() {
        // The app sends no pixels and no OCR; the prompt must not tell the
        // model to use "the visible text and the image description".
        let prompt = RuleTemplate.screenshots.makeRule().prompt.lowercased()
        XCTAssertFalse(prompt.contains("visible text"))
        XCTAssertFalse(prompt.contains("sichtbaren text"))
    }
}
