import XCTest
@testable import OpenSuperWhisper

final class VoiceWorkflowValidationTests: XCTestCase {
    func testNormalizedAlias_collapsesWhitespaceAndBoundaryPunctuation() {
        XCTAssertEqual(
            VoiceWorkflowValidator.normalizedAlias("  \"Open   Note!\"  "),
            "open note"
        )
    }

    func testValidate_nameRequired() {
        let workflow = VoiceWorkflow(
            name: " ",
            aliases: ["obsidian"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        XCTAssertTrue(
            VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
                .contains(.missingName)
        )
    }

    func testValidate_aliasRequired() {
        let workflow = VoiceWorkflow(
            name: "Obsidian",
            aliases: [],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        XCTAssertTrue(
            VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
                .contains(.missingAlias)
        )
    }

    func testValidate_duplicateAliasAcrossWorkflowsRejected() {
        let existing = VoiceWorkflow(
            name: "Existing",
            aliases: ["obsidian"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )
        let duplicate = VoiceWorkflow(
            name: "Duplicate",
            aliases: [" Obsidian! "],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        let errors = VoiceWorkflowValidator.validate(workflow: duplicate, duringSaveAgainst: [existing])
        XCTAssertTrue(errors.contains(.duplicateAlias("obsidian")))
    }

    func testValidate_duplicateAliasInsideWorkflowRejected() {
        let workflow = VoiceWorkflow(
            name: "Duplicate",
            aliases: ["obsidian", "Obsidian"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        let errors = VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
        XCTAssertTrue(errors.contains(.duplicateAlias("obsidian")))
    }

    func testValidate_invalidExecutablePathRejected() {
        let workflow = VoiceWorkflow(
            name: "Obsidian",
            aliases: ["obsidian"],
            executablePath: "relative/path",
            arguments: ["{text}"]
        )

        let errors = VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
        XCTAssertTrue(errors.contains(.executablePathMustBeAbsolute))
    }

    func testValidate_missingTextPlaceholderRejected() {
        let workflow = VoiceWorkflow(
            name: "Obsidian",
            aliases: ["obsidian"],
            executablePath: "/bin/echo",
            arguments: ["payload"]
        )

        let errors = VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
        XCTAssertTrue(errors.contains(.missingTextPlaceholder))
    }

    func testValidate_shellWorkflowRequiresCommand() {
        let workflow = VoiceWorkflow(
            name: "Shell",
            aliases: ["shell"],
            launchMode: .shell,
            executablePath: "",
            arguments: [],
            shellCommand: " "
        )

        let errors = VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
        XCTAssertTrue(errors.contains(.missingShellCommand))
    }

    func testValidate_shellWorkflowRequiresPayloadReference() {
        let workflow = VoiceWorkflow(
            name: "Shell",
            aliases: ["shell"],
            launchMode: .shell,
            executablePath: "",
            arguments: [],
            shellCommand: "obsidian append --active"
        )

        let errors = VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
        XCTAssertTrue(errors.contains(.missingShellPayloadReference))
    }

    func testValidate_shellWorkflowAcceptsPayloadEnvironmentVariable() {
        let workflow = VoiceWorkflow(
            name: "Shell",
            aliases: ["shell"],
            launchMode: .shell,
            executablePath: "",
            arguments: [],
            shellCommand: #"obsidian append content="$OPENSUPERWHISPER_WORKFLOW_TEXT" --active"#
        )

        let errors = VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: [])
        XCTAssertFalse(errors.contains(.missingShellCommand))
        XCTAssertFalse(errors.contains(.missingShellPayloadReference))
    }
}
