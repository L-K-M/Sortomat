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

    func testEqualPrioritiesKeepListOrderAtScale() {
        // Stability is now guaranteed by an explicit index tiebreak rather
        // than an (undocumented) property of Swift's sort — assert it holds
        // for a list large enough that an unstable sort would likely reorder.
        let names = (0..<100).map { "rule-\($0)" }
        let rules = names.map { rule($0, priority: 7) }
        XCTAssertEqual(rules.inExecutionOrder().map(\.name), names)
    }

    func testTiebreakOnlyAppliesWithinEqualPriority() {
        let rules = [
            rule("b1", priority: 1), rule("a1", priority: 2),
            rule("b2", priority: 1), rule("a2", priority: 2),
        ]
        XCTAssertEqual(rules.inExecutionOrder().map(\.name), ["a1", "a2", "b1", "b2"])
    }
}
