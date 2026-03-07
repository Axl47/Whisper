import XCTest
@testable import OpenSuperWhisper

final class VoiceWorkflowExecutorTests: XCTestCase {
    func testSubstitutedArguments_preservesPayloadAsSingleArgument() {
        let arguments = VoiceWorkflowExecutor.substitutedArguments(
            arguments: ["--payload", "{text}"],
            payload: "buy milk tomorrow"
        )

        XCTAssertEqual(arguments, ["--payload", "buy milk tomorrow"])
    }

    func testSubstitutedArguments_replacesMultiplePlaceholders() {
        let arguments = VoiceWorkflowExecutor.substitutedArguments(
            arguments: ["prefix={text}", "{text}", "suffix={text}"],
            payload: "payload"
        )

        XCTAssertEqual(arguments, ["prefix=payload", "payload", "suffix=payload"])
    }

    func testSubstitutedShellCommand_shellEscapesPayload() {
        let command = VoiceWorkflowExecutor.substitutedShellCommand(
            command: "printf %s {text}",
            payload: "buy milk's tomorrow"
        )

        XCTAssertEqual(command, "printf %s 'buy milk'\"'\"'s tomorrow'")
    }

    func testExecute_runsDirectProcessWithoutShell() async {
        let workflow = VoiceWorkflow(
            name: "Python",
            aliases: ["python"],
            executablePath: "/usr/bin/python3",
            arguments: [
                "-c",
                "import sys; print(sys.argv[1])",
                "{text}"
            ]
        )

        let result = await VoiceWorkflowExecutor.execute(workflow: workflow, payload: "buy milk tomorrow")

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "buy milk tomorrow")
        XCTAssertNil(result.message)
    }

    func testExecute_runsShellCommandWithPayloadEnvironmentVariable() async {
        let workflow = VoiceWorkflow(
            name: "Shell",
            aliases: ["shell"],
            launchMode: .shell,
            executablePath: "",
            arguments: [],
            shellCommand: #"printf '%s' "$OPENSUPERWHISPER_WORKFLOW_TEXT""#
        )

        let result = await VoiceWorkflowExecutor.execute(workflow: workflow, payload: #"buy "milk" tomorrow"#)

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, #"buy "milk" tomorrow"#)
        XCTAssertNil(result.message)
    }
}
