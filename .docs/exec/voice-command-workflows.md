# Voice Workflow Commands for Live Recordings

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

After this change, live microphone recordings can trigger named voice workflows instead of always pasting text. A user will be able to define aliases such as `obsidian`, speak `obsidian buy milk tomorrow`, and have the app run a configured executable with `buy milk tomorrow` as the payload while still saving a tagged recording in history. The mini recorder popup will also make workflow runs visible with success or failure messaging and workflow-specific accent styling.

## Progress

- [x] (2026-03-07 00:35Z) Created the ExecPlan and working list before implementation started.
- [x] Implemented workflow persistence in `OpenSuperWhisper/Utils/AppPreferences.swift` and `OpenSuperWhisper/Models/Recording.swift`.
- [x] Implemented workflow matching, validation, execution, and shared live recording coordination under `OpenSuperWhisper/Workflows/`.
- [x] Refactored `OpenSuperWhisper/ContentView.swift` and `OpenSuperWhisper/Indicator/IndicatorWindow.swift` to use the shared coordinator.
- [x] Added workflow settings UI in `OpenSuperWhisper/Settings.swift`.
- [x] Added history badges, failure UI, and popup result/accent rendering.
- [x] Added tests for validation, matching, persistence, migration, and execution behavior.
- [x] Ran targeted workflow test coverage and the macOS `xcodebuild test` command, then recorded outcomes.
- [x] Updated `AGENTS.md` with workflow-specific implementation notes.

## Surprises & Discoveries

- Observation: The Xcode project uses filesystem-synchronized groups.
  Evidence: `OpenSuperWhisper.xcodeproj/project.pbxproj` contains `PBXFileSystemSynchronizedRootGroup`, so new Swift files under tracked folders do not require manual project-file edits.
- Observation: `./run.sh build` is not reliable in this local environment unless `cmake` is installed first.
  Evidence: the script exits immediately with `./run.sh:10: command not found: cmake`.
- Observation: validating against the workspace-local `SourcePackages` checkout required a small local Swift 6.2 compatibility patch in FluidAudio before the app target would compile.
  Evidence: `SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Streaming/StreamingAsrManager.swift` needed removal of `nonisolated(unsafe)` from a few stored properties, and the repo already documents using `xcodebuild -clonedSourcePackagesDirPath SourcePackages ...` for this style of local dependency validation.

## Decision Log

- Decision: Keep workflow matching engine-agnostic and apply it only to live microphone recordings after the final transcript is produced.
  Rationale: The existing transcription service already abstracts Whisper and Parakeet, while imported-file transcription and regeneration use separate queue-driven flows that must remain unchanged.
  Date/Author: 2026-03-07 / Codex

- Decision: Keep workflow execution failures as `Recording.status = .completed` and represent workflow results in dedicated metadata.
  Rationale: Audio transcription succeeded, so using the existing transcription failure status would conflate decode failures with downstream delivery failures.
  Date/Author: 2026-03-07 / Codex

- Decision: Store an optional per-workflow popup accent color.
  Rationale: The mini recorder popup can visually confirm that a workflow was detected without forcing every workflow to define a color.
  Date/Author: 2026-03-07 / Codex

## Outcomes & Retrospective

Implementation landed across persistence, workflow coordination, settings, history UI, and the mini recorder popup. The popup now carries a workflow-specific accent border/glow and retains the accent through the short result state, while the workflows settings tab uses the same Liquid Glass visual direction as the refreshed overlay.

Validation outcomes:

- `./run.sh build` could not be completed locally because `cmake` is not installed in this environment.
- `xcodebuild test -clonedSourcePackagesDirPath SourcePackages -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO` completed successfully after using the local `SourcePackages` FluidAudio compatibility patch.
- `xcodebuild test ... -only-testing:OpenSuperWhisperTests` still exposes pre-existing unrelated failures in clipboard and microphone integration tests.
- The new workflow-focused suites passed cleanly when run explicitly:

      xcodebuild test -clonedSourcePackagesDirPath SourcePackages -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO \
        -only-testing:OpenSuperWhisperTests/VoiceWorkflowMatcherTests \
        -only-testing:OpenSuperWhisperTests/VoiceWorkflowValidationTests \
        -only-testing:OpenSuperWhisperTests/VoiceWorkflowPersistenceTests \
        -only-testing:OpenSuperWhisperTests/RecordingMigrationTests \
        -only-testing:OpenSuperWhisperTests/VoiceWorkflowExecutorTests

## Context and Orientation

`OpenSuperWhisper/ContentView.swift` owns the main-window recorder path and currently performs recording finalization inline. `OpenSuperWhisper/Indicator/IndicatorWindow.swift` owns the mini recorder popup and hotkey flow, including the live Whisper hold-to-record path. `OpenSuperWhisper/TranscriptionService.swift` performs final transcription and must keep the existing `preserveDisplayedText: true` behavior for the live Whisper hotkey final pass so the popup retains the last live preview while the final batch decode runs. `OpenSuperWhisper/Utils/AppPreferences.swift` is a `UserDefaults`-backed singleton, so new workflow preferences must be stored as encoded data. `OpenSuperWhisper/Models/Recording.swift` owns the GRDB migration chain and recording persistence. Imported audio files flow through `OpenSuperWhisper/TranscriptionQueue.swift`; that path is explicitly out of scope for workflow execution.

In this repository, a “workflow” means a saved executable path and argument template that are run directly with `Process` when a live transcript begins with one of the workflow’s aliases. The payload is the remaining text after the alias. A “live recording” means microphone capture started either from the main window recorder button or the mini recorder hotkey flow, not a dragged-in file or queued transcription job.

## Plan of Work

First, extend the persisted models. Add workflow preferences to `AppPreferences`, define a `VoiceWorkflow` model plus validation helpers, and extend `Recording` with delivery metadata plus a new migration. Refactor the migrator into a reusable helper so tests can verify migration behavior in memory.

Second, add the workflow engine under `OpenSuperWhisper/Workflows/`. This includes the matcher, executor, and a shared live recording coordinator that transcribes audio, decides whether a workflow matches, persists the final recording, and returns either paste text or a workflow result message.

Third, rewire the two live recording entry points. `ContentViewModel.startDecoding()` will call the coordinator in history-only mode. `IndicatorViewModel.startDecoding()` will call the coordinator in paste-if-not-workflow mode, and the Whisper hotkey final path will continue to pass `preserveDisplayedText: true`.

Fourth, add the Workflows settings tab and editor sheet, then update the recording history row and popup UI to surface workflow badges, failures, and popup accent styling.

Finally, add automated tests and run the build plus test commands from the repository root. Update this plan, the working list, and `AGENTS.md` with any notable implementation discoveries.

## Concrete Steps

Run from `/Users/axel/Desktop/Code_Projects/Personal/Whisper`.

1. Implement persistence and workflow support types.
2. Refactor live recording completion to use the new coordinator.
3. Implement settings and UI updates.
4. Add tests under `OpenSuperWhisperTests/`.
5. Run:

       ./run.sh build
       xcodebuild test -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO

Expected outcome after implementation: the build succeeds, the new tests pass, and the manual `Obsidian buy milk tomorrow` scenario runs the configured command without pasting text.

## Validation and Acceptance

Acceptance is behavioral. A configured workflow should run only for live microphone recordings whose final transcript begins with a saved alias and contains non-empty payload text. The saved recording row must show `Workflow`, the workflow name, and the payload text without the alias. Alias-only utterances must not paste or execute, but they must save a workflow-tagged recording with the user-facing failure message. Non-matching live transcripts must preserve the existing main-window save-only and mini-recorder paste behavior. The popup should display a short success or failure message and, when a workflow has an accent color, tint the popup border and glow during the detected/result state.

## Idempotence and Recovery

The migrations are additive and safe to rerun through GRDB’s migrator. Workflow settings changes are persisted only on successful editor save, so a failed validation leaves existing workflows untouched. If command execution fails, the audio file and history entry are still saved so the user can inspect what happened. If a transcription fails before a recording is created, the temporary audio file should be deleted and no workflow action should be attempted.

## Artifacts and Notes

Important example manual workflow configuration:

    executable: /usr/bin/python3
    arguments:
      - -c
      - import pathlib, sys; pathlib.Path('/tmp/whisper-workflow.txt').write_text(sys.argv[1], encoding='utf-8')
      - {text}

Important workflow failure message string:

    Voice workflow aliases must be followed by content.

## Interfaces and Dependencies

Add `OpenSuperWhisper/Workflows/VoiceWorkflow.swift` with:

    struct VoiceWorkflow: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        var name: String
        var isEnabled: Bool
        var aliases: [String]
        var executablePath: String
        var arguments: [String]
        var accentColorHex: String?
    }

Add `OpenSuperWhisper/Workflows/VoiceWorkflowValidation.swift` with:

    enum VoiceWorkflowValidationError: Equatable
    struct VoiceWorkflowValidator {
        static func validate(workflow: VoiceWorkflow, duringSaveAgainst existing: [VoiceWorkflow]) -> [VoiceWorkflowValidationError]
        static func normalizedAlias(_ alias: String) -> String
    }

Add `OpenSuperWhisper/Workflows/VoiceWorkflowMatcher.swift` with:

    struct WorkflowMatch: Equatable {
        let workflow: VoiceWorkflow
        let payload: String
    }

    struct VoiceWorkflowMatcher {
        static func match(transcript: String, workflows: [VoiceWorkflow], isEnabled: Bool) -> WorkflowMatch?
    }

Add `OpenSuperWhisper/Workflows/VoiceWorkflowExecutor.swift` with:

    struct WorkflowExecutionResult: Equatable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let status: WorkflowExecutionStatus
        let message: String?
    }

    enum VoiceWorkflowExecutor {
        static func execute(workflow: VoiceWorkflow, payload: String) async -> WorkflowExecutionResult
    }

Add `OpenSuperWhisper/Workflows/LiveRecordingCoordinator.swift` with:

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
        func finalizeRecording(
            tempURL: URL,
            duration: TimeInterval,
            settings: Settings,
            deliveryTarget: LiveRecordingDeliveryTarget,
            preserveDisplayedText: Bool = false
        ) async throws -> LiveRecordingCompletionResult
    }

Plan revision note: added popup accent color support because the product discussion established that workflow detection should visually tint the mini recorder popup using an optional per-workflow color.
