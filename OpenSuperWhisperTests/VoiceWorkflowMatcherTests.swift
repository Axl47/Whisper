import XCTest
@testable import OpenSuperWhisper

final class VoiceWorkflowMatcherTests: XCTestCase {
    private let obsidian = VoiceWorkflow(
        name: "Obsidian",
        aliases: ["obsidian"],
        executablePath: "/bin/echo",
        arguments: ["{text}"]
    )

    func testMatch_exactAliasMatch_returnsPayload() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "obsidian buy milk",
            workflows: [obsidian],
            isEnabled: true
        )

        XCTAssertEqual(match?.workflow.name, "Obsidian")
        XCTAssertEqual(match?.payload, "buy milk")
    }

    func testMatch_multiWordAlias_returnsPayload() {
        let workflow = VoiceWorkflow(
            name: "Draft",
            aliases: ["create note"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        let match = VoiceWorkflowMatcher.match(
            transcript: "Create note meeting recap",
            workflows: [workflow],
            isEnabled: true
        )

        XCTAssertEqual(match?.payload, "meeting recap")
    }

    func testMatch_punctuationAfterAlias_returnsPayload() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "obsidian: buy milk",
            workflows: [obsidian],
            isEnabled: true
        )

        XCTAssertEqual(match?.payload, "buy milk")
    }

    func testMatch_periodAfterAlias_trimsLeadingPunctuationFromPayload() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "obsidian. so i'm testing",
            workflows: [obsidian],
            isEnabled: true
        )

        XCTAssertEqual(match?.payload, "so i'm testing")
    }

    func testMatch_timestampPrefixedTranscript_stripsPrefix() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "[0.0->1.2] obsidian buy milk",
            workflows: [obsidian],
            isEnabled: true
        )

        XCTAssertEqual(match?.payload, "buy milk")
    }

    func testMatch_longestAliasWins() {
        let short = VoiceWorkflow(
            name: "Short",
            aliases: ["open"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )
        let long = VoiceWorkflow(
            name: "Long",
            aliases: ["open note"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        let match = VoiceWorkflowMatcher.match(
            transcript: "open note project brief",
            workflows: [short, long],
            isEnabled: true
        )

        XCTAssertEqual(match?.workflow.name, "Long")
        XCTAssertEqual(match?.payload, "project brief")
    }

    func testMatch_noMatchFallback_returnsNil() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "buy milk tomorrow",
            workflows: [obsidian],
            isEnabled: true
        )

        XCTAssertNil(match)
    }

    func testMatch_aliasOnlyFailure_returnsEmptyPayload() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "obsidian",
            workflows: [obsidian],
            isEnabled: true
        )

        XCTAssertEqual(match?.payload, "")
    }

    func testMatch_disabledWorkflowIgnored() {
        let disabledWorkflow = VoiceWorkflow(
            name: "Obsidian",
            isEnabled: false,
            aliases: ["obsidian"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        let match = VoiceWorkflowMatcher.match(
            transcript: "obsidian buy milk",
            workflows: [disabledWorkflow],
            isEnabled: true
        )

        XCTAssertNil(match)
    }

    func testMatch_masterToggleOffIgnored() {
        let match = VoiceWorkflowMatcher.match(
            transcript: "obsidian buy milk",
            workflows: [obsidian],
            isEnabled: false
        )

        XCTAssertNil(match)
    }
}
