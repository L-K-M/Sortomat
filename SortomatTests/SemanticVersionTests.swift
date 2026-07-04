import XCTest
@testable import Sortomat

final class SemanticVersionTests: XCTestCase {
    func testParsesAndStripsLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(SemanticVersion("1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(SemanticVersion("  V2.0  ")?.components, [2, 0])
    }

    func testRejectsGarbage() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("1.x.3"))
    }

    func testComparisonIsNumericNotLexical() {
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.0")!)
        XCTAssertTrue(SemanticVersion("2.0.0")! > SemanticVersion("1.999.0")!)
    }

    func testZeroPaddingEquivalence() {
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion("1.2.0"))
        XCTAssertFalse(SemanticVersion("1.2")! < SemanticVersion("1.2.0")!)
    }

    func testPrereleaseSortsBelowFinal() {
        XCTAssertTrue(SemanticVersion("1.2.0-beta.1")! < SemanticVersion("1.2.0")!)
        XCTAssertTrue(SemanticVersion("1.2.0")! > SemanticVersion("1.2.0-rc.1")!)
    }

    func testPrereleaseNumericOrdering() {
        XCTAssertTrue(SemanticVersion("1.4.0-beta.2")! < SemanticVersion("1.4.0-beta.10")!)
    }

    func testIgnoresBuildMetadata() {
        XCTAssertEqual(SemanticVersion("1.2.3+build.99"), SemanticVersion("1.2.3"))
    }

    func testNewerDetection() {
        let current = SemanticVersion("1.0")!
        XCTAssertTrue(SemanticVersion("1.0.1")! > current)
        XCTAssertFalse(SemanticVersion("0.9")! > current)
    }
}
