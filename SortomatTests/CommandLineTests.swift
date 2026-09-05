import XCTest
@testable import Sortomat

final class CommandLineTests: XCTestCase {
    func testKnownCommandsParse() {
        XCTAssertEqual(HeadlessRunner.command(for: "scan-once"), .scanOnce)
        XCTAssertEqual(HeadlessRunner.command(for: "preview"), .preview)
        XCTAssertEqual(HeadlessRunner.command(for: "undo"), .undo)
        XCTAssertEqual(HeadlessRunner.command(for: "--help"), .help)
        XCTAssertEqual(HeadlessRunner.command(for: "-h"), .help)
        XCTAssertEqual(HeadlessRunner.command(for: "help"), .help)
        XCTAssertEqual(HeadlessRunner.command(for: "--version"), .version)
        XCTAssertNil(HeadlessRunner.command(for: "scanonce"))
    }

    func testTypoIsACommandLineInvocationNotAGUILaunch() {
        // A typo'd launchd job must fail loudly, not boot a second GUI.
        XCTAssertTrue(SortomatMain.isCommandLineInvocation("scanonce"))
        XCTAssertTrue(SortomatMain.isCommandLineInvocation("scan-once"))
        XCTAssertTrue(SortomatMain.isCommandLineInvocation("--help"))
    }

    func testLaunchFlagsStillMeanTheApp() {
        XCTAssertFalse(SortomatMain.isCommandLineInvocation("-NSDocumentRevisionsDebugMode"))
        XCTAssertFalse(SortomatMain.isCommandLineInvocation("-psn_0_12345"))
    }

    func testUsageMentionsEveryCommand() {
        let usage = HeadlessRunner.usage
        for command in HeadlessRunner.Command.allCases {
            XCTAssertTrue(usage.contains(command.rawValue), "usage must document \(command.rawValue)")
        }
    }
}
