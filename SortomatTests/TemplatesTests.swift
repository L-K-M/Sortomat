import Foundation
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


    func testLegacyAndLocalizedScreenshotNamesReachTheModel() {
        let rule = RuleTemplate.screenshots.makeRule()
        func decision(for name: String) -> DeterministicEngine.Decision {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? Data("x".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return DeterministicEngine.evaluate(rule: rule, file: url)
        }
        // Pre-Big-Sur macOS wrote "Screen Shot …" with a space — no "creenshot"
        // substring, so the catch-all skip swallowed those files entirely.
        XCTAssertEqual(decision(for: "Screen Shot 2019-04-01 at 10.00.00.png"), .useLLM)
        XCTAssertEqual(decision(for: "Capture d'écran 2024-01-01.png"), .useLLM)
        XCTAssertEqual(decision(for: "Captura de pantalla 2024-01-01.png"), .useLLM)
    }

    // MARK: - The one template that needs no key

    /// A stub fact source, so what the tidy template decides is pinned without
    /// a file system and without Launch Services.
    private struct Kinded: FactSource {
        var resolved: Kind
        func kind() -> Kind? { resolved }
    }

    private func tidyPlacement(_ name: String, kind: Kind) -> Placement? {
        let rule = RuleTemplate.tidy.makeRule()
        let root = URL(fileURLWithPath: "/watch")
        let facts = FileFacts(url: root.appendingPathComponent(name), watchRoot: root,
                              source: Kinded(resolved: kind))
        let context = RuleEvaluator.Context(rule: rule, facts: facts,
                                            timeZone: TimeZone(identifier: "UTC")!,
                                            allowModel: false)
        guard case .decided(let placement, _) = RuleEvaluator.evaluate(context) else { return nil }
        return placement
    }

    func testTheTidyTemplateFilesByKindWithoutAModel() throws {
        let image = try XCTUnwrap(tidyPlacement("holiday.png", kind: .image))
        XCTAssertEqual(image.operation, .move)
        XCTAssertEqual(image.relativePath?.string(),
                       "\(L10n.t("template.tidy.folder.images"))/holiday.png")

        let document = try XCTUnwrap(tidyPlacement("lease.pdf", kind: .pdf))
        XCTAssertEqual(document.relativePath?.string(),
                       "\(L10n.t("template.tidy.folder.documents"))/lease.pdf")

        let archive = try XCTUnwrap(tidyPlacement("backup.zip", kind: .archive))
        XCTAssertEqual(archive.relativePath?.string(),
                       "\(L10n.t("template.tidy.folder.archives"))/backup.zip")
    }

    func testTheTidyTemplateLeavesWhatItDoesNotRecognizeAlone() throws {
        // The fallback is `skip`, not `askModel`: a tidy-up rule that starts
        // spending money on the files it did not understand would be the
        // opposite of what it says on the tin.
        let rule = RuleTemplate.tidy.makeRule()
        XCTAssertEqual(rule.fallback, .skip)
        XCTAssertTrue(rule.prompt.isEmpty, "nothing here should reach the model")
        XCTAssertTrue(rule.taxonomy.isEmpty)

        let other = try XCTUnwrap(tidyPlacement("thing.xyz", kind: .other))
        XCTAssertEqual(other.operation, .skip)
        XCTAssertNil(other.relativePath)
    }

    func testEveryTidyStepKeepsTheFileName() {
        // The one thing a tidy-up rule must never get wrong.
        for step in RuleTemplate.tidySteps {
            let template = step.placement?.template ?? ""
            XCTAssertTrue(template.hasSuffix("/{name}"), "\(step.name): «\(template)»")
        }
    }

    func testTheTidyTemplatePassesItsOwnValidator() {
        var rule = RuleTemplate.tidy.makeRule()
        rule.watchPath = "~/Downloads"
        rule.targetPath = "~/Downloads"
        XCTAssertEqual(RuleValidator.findings(for: rule), [],
                       "a template must not ship with something to complain about")
    }
}
