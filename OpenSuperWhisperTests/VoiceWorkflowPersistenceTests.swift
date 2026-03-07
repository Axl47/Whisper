import XCTest
@testable import OpenSuperWhisper

final class VoiceWorkflowPersistenceTests: XCTestCase {
    func testVoiceWorkflow_roundTripsThroughJSON() throws {
        let workflow = VoiceWorkflow(
            name: "Obsidian",
            aliases: ["obsidian", "create note"],
            launchMode: .shell,
            executablePath: "/bin/echo",
            arguments: ["--payload", "{text}"],
            shellCommand: #"obsidian append content="$OPENSUPERWHISPER_WORKFLOW_TEXT" --active"#,
            accentColorHex: "8844CCFF"
        )

        let data = try JSONEncoder().encode(workflow)
        let decoded = try JSONDecoder().decode(VoiceWorkflow.self, from: data)
        XCTAssertEqual(decoded, workflow)
    }

    func testVoiceWorkflow_decodesLegacyExecutableWorkflows() throws {
        let data = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Obsidian",
          "isEnabled": true,
          "aliases": ["obsidian"],
          "executablePath": "/bin/echo",
          "arguments": ["{text}"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(VoiceWorkflow.self, from: data)
        XCTAssertEqual(decoded.launchMode, .executable)
        XCTAssertEqual(decoded.shellCommand, "")
    }

    func testAppPreferences_voiceWorkflowsRoundTrip() {
        let preferences = AppPreferences.shared
        let originalWorkflows = preferences.voiceWorkflows
        let originalEnabled = preferences.voiceWorkflowsEnabled

        let workflow = VoiceWorkflow(
            name: "Obsidian",
            aliases: ["obsidian"],
            executablePath: "/bin/echo",
            arguments: ["{text}"]
        )

        defer {
            preferences.voiceWorkflows = originalWorkflows
            preferences.voiceWorkflowsEnabled = originalEnabled
        }

        preferences.voiceWorkflowsEnabled = true
        preferences.voiceWorkflows = [workflow]

        XCTAssertTrue(preferences.voiceWorkflowsEnabled)
        XCTAssertEqual(preferences.voiceWorkflows, [workflow])
    }

    func testRecording_roundTripsWithWorkflowMetadata() throws {
        let recording = Recording(
            id: UUID(),
            timestamp: Date(),
            fileName: "sample.wav",
            transcription: "buy milk",
            duration: 2.0,
            status: .completed,
            progress: 1.0,
            sourceFileURL: nil,
            deliveryKind: .workflow,
            workflowName: "Obsidian",
            workflowExecutionStatus: .failed,
            workflowExecutionMessage: "Voice workflow aliases must be followed by content."
        )

        let data = try JSONEncoder().encode(recording)
        let decoded = try JSONDecoder().decode(Recording.self, from: data)

        XCTAssertEqual(decoded.deliveryKind, .workflow)
        XCTAssertEqual(decoded.workflowName, "Obsidian")
        XCTAssertEqual(decoded.workflowExecutionStatus, .failed)
        XCTAssertEqual(decoded.workflowExecutionMessage, "Voice workflow aliases must be followed by content.")
    }
}
