import Foundation

enum LiveRecordingDeliveryTarget {
    case historyOnly
    case pasteIfNotWorkflow
}

struct IndicatorOutcomeMessage: Equatable {
    let text: String
    let isError: Bool
    let accentColorHex: String?
}

struct LiveRecordingCompletionResult {
    let recording: Recording
    let pasteText: String?
    let indicatorMessage: IndicatorOutcomeMessage?
}

@MainActor
final class LiveRecordingCoordinator {
    static let shared = LiveRecordingCoordinator()

    private let transcriptionService: TranscriptionService
    private let recordingStore: RecordingStore
    private let recorder: AudioRecorder
    private let preferences: AppPreferences

    init(
        transcriptionService: TranscriptionService = .shared,
        recordingStore: RecordingStore = .shared,
        recorder: AudioRecorder = .shared,
        preferences: AppPreferences = .shared
    ) {
        self.transcriptionService = transcriptionService
        self.recordingStore = recordingStore
        self.recorder = recorder
        self.preferences = preferences
    }

    func finalizeRecording(
        tempURL: URL,
        duration: TimeInterval,
        settings: Settings,
        deliveryTarget: LiveRecordingDeliveryTarget,
        preserveDisplayedText: Bool = false
    ) async throws -> LiveRecordingCompletionResult {
        let transcript = try await transcriptionService.transcribeAudio(
            url: tempURL,
            settings: settings,
            preserveDisplayedText: preserveDisplayedText
        )

        let match = VoiceWorkflowMatcher.match(
            transcript: transcript,
            workflows: preferences.voiceWorkflows,
            isEnabled: preferences.voiceWorkflowsEnabled
        )

        let timestamp = Date()
        let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
        let recordingId = UUID()

        let recording: Recording
        let pasteText: String?
        let indicatorMessage: IndicatorOutcomeMessage?
        let pendingWorkflowTask: Task<WorkflowExecutionResult, Never>?

        if let match {
            if match.payload.isEmpty {
                recording = Recording(
                    id: recordingId,
                    timestamp: timestamp,
                    fileName: fileName,
                    transcription: "",
                    duration: duration,
                    status: .completed,
                    progress: 1.0,
                    sourceFileURL: nil,
                    deliveryKind: .workflow,
                    workflowName: match.workflow.name,
                    workflowExecutionStatus: .failed,
                    workflowExecutionMessage: "Voice workflow aliases must be followed by content."
                )
                pasteText = nil
                indicatorMessage = IndicatorOutcomeMessage(
                    text: "\(match.workflow.name) failed: Voice workflow aliases must be followed by content.",
                    isError: true,
                    accentColorHex: match.workflow.accentColorHex
                )
                pendingWorkflowTask = nil
            } else {
                let executionHandle = await VoiceWorkflowExecutor.start(
                    workflow: match.workflow,
                    payload: match.payload
                )

                pasteText = nil

                if let execution = executionHandle.immediateResult {
                    let workflowMessage = VoiceWorkflowExecutor.truncatedMessage(execution.message)

                    recording = Recording(
                        id: recordingId,
                        timestamp: timestamp,
                        fileName: fileName,
                        transcription: match.payload,
                        duration: duration,
                        status: .completed,
                        progress: 1.0,
                        sourceFileURL: nil,
                        deliveryKind: .workflow,
                        workflowName: match.workflow.name,
                        workflowExecutionStatus: execution.status,
                        workflowExecutionMessage: workflowMessage
                    )
                    indicatorMessage = IndicatorOutcomeMessage(
                        text: execution.status == .succeeded
                            ? "Ran \(match.workflow.name)"
                            : "\(match.workflow.name) failed: \(workflowMessage ?? "Command failed.")",
                        isError: execution.status == .failed,
                        accentColorHex: match.workflow.accentColorHex
                    )
                    pendingWorkflowTask = nil
                } else {
                    recording = Recording(
                        id: recordingId,
                        timestamp: timestamp,
                        fileName: fileName,
                        transcription: match.payload,
                        duration: duration,
                        status: .completed,
                        progress: 1.0,
                        sourceFileURL: nil,
                        deliveryKind: .workflow,
                        workflowName: match.workflow.name,
                        workflowExecutionStatus: .running,
                        workflowExecutionMessage: nil
                    )
                    indicatorMessage = IndicatorOutcomeMessage(
                        text: "Running \(match.workflow.name)",
                        isError: false,
                        accentColorHex: match.workflow.accentColorHex
                    )
                    pendingWorkflowTask = executionHandle.pendingResultTask
                }
            }
        } else {
            recording = Recording(
                id: recordingId,
                timestamp: timestamp,
                fileName: fileName,
                transcription: transcript,
                duration: duration,
                status: .completed,
                progress: 1.0,
                sourceFileURL: nil,
                deliveryKind: .transcription,
                workflowName: nil,
                workflowExecutionStatus: nil,
                workflowExecutionMessage: nil
            )
            pasteText = deliveryTarget == .pasteIfNotWorkflow ? transcript : nil
            indicatorMessage = nil
            pendingWorkflowTask = nil
        }

        try recorder.moveTemporaryRecording(from: tempURL, to: recording.url)
        try await recordingStore.addRecordingSync(recording)

        if let pendingWorkflowTask {
            observeWorkflowExecution(
                task: pendingWorkflowTask,
                recordingId: recordingId
            )
        }

        return LiveRecordingCompletionResult(
            recording: recording,
            pasteText: pasteText,
            indicatorMessage: indicatorMessage
        )
    }

    private func observeWorkflowExecution(
        task: Task<WorkflowExecutionResult, Never>,
        recordingId: UUID
    ) {
        Task { [recordingStore] in
            let execution = await task.value
            await recordingStore.updateWorkflowExecutionSync(
                recordingId,
                status: execution.status,
                message: VoiceWorkflowExecutor.truncatedMessage(execution.message)
            )
        }
    }
}
