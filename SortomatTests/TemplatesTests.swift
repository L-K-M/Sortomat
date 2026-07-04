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
}
