import XCTest
@testable import Sortomat

final class RuleOrderTests: XCTestCase {
    private func rule(_ name: String, priority: Int, enabled: Bool = true) -> Rule {
        Rule(name: name, enabled: enabled, priority: priority)
    }

    func testHigherPriorityRunsFirst() {
        let rules = [rule("low", priority: 1), rule("high", priority: 10)]
        XCTAssertEqual(rules.inExecutionOrder().map(\.name), ["high", "low"])
    }

    func testEqualPrioritiesKeepListOrder() {
        let rules = [rule("a", priority: 5), rule("b", priority: 5), rule("c", priority: 5)]
        XCTAssertEqual(rules.inExecutionOrder().map(\.name), ["a", "b", "c"])
    }

    func testDisabledRulesAreExcluded() {
        let rules = [rule("on", priority: 0), rule("off", priority: 100, enabled: false)]
        XCTAssertEqual(rules.inExecutionOrder().map(\.name), ["on"])
    }
}
