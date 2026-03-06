# Live Whisper Hotkey Streaming

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

After this change, holding the Whisper hotkey should start a live dictation session inside the popup instead of waiting for a full-file transcription after release. Users should see stable text stream inside the popup while they are still holding the hotkey, and on release the target app should receive one final paste from the existing batch-quality Whisper pass. The saved recording/history entry should use that same final batch transcript.

The first version is intentionally narrow. It applies only to the hotkey hold-to-record flow when `AppPreferences.selectedEngine == "whisper"`. Manual recording from the main window and all FluidAudio paths remain on the existing batch transcription path.

## Progress

- [x] (2026-03-06 00:00Z) Investigated the current hotkey, insertion, and engine architecture to ground the design.
- [x] (2026-03-06 01:30Z) Created the ExecPlan and working list artifacts used during implementation.
- [x] (2026-03-06 04:50Z) Implemented live PCM hotkey capture in `OpenSuperWhisper/AudioRecorder.swift` while preserving the existing `AVAudioRecorder` path for manual recordings and non-live callers.
- [x] (2026-03-06 05:10Z) Implemented the rolling live Whisper session, committed/preview state handling, and live insertion coordination in `OpenSuperWhisper/TranscriptionService.swift`.
- [x] (2026-03-06 05:20Z) Implemented accessibility-based focused text insertion with release-time paste fallback in `OpenSuperWhisper/Utils/FocusUtils.swift`.
- [x] (2026-03-06 05:30Z) Wired `OpenSuperWhisper/Indicator/IndicatorWindow.swift` and `OpenSuperWhisper/ShortcutManager.swift` to start live streaming on key down and finalize on key up.
- [x] (2026-03-06 05:53Z) Added focused unit tests for rolling commit logic and fallback buffering in `OpenSuperWhisperTests/OpenSuperWhisperTests.swift`.
- [x] (2026-03-06 05:54Z) Verified the scheme builds with `xcodebuild build ... -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`.
- [x] (2026-03-06 05:53Z) Verified the new targeted tests pass with `xcodebuild test ... -only-testing:OpenSuperWhisperTests/LiveTranscriptionAccumulatorTests -only-testing:OpenSuperWhisperTests/BufferedTextInsertionStateTests`.
- [x] (2026-03-06 14:10Z) Switched live deduplication from segment-only boundaries to token timestamps in `OpenSuperWhisper/Engines/WhisperEngine.swift` and `OpenSuperWhisper/TranscriptionService.swift`, then re-ran the focused tests and a full build.
- [x] (2026-03-06 14:20Z) Fixed the live AX insertion session to carry its insertion range forward between writes, stripped Whisper control tokens / the known silence hallucination phrase from live transcript assembly, and re-ran focused tests plus a full build.
- [x] (2026-03-06 14:31Z) Tightened the token-based live accumulator to commit only at safe word boundaries, added single-word overlap handling for token-backed updates, relaxed AX insertion to survive focused-element proxy churn within the same app, and re-ran focused tests plus a full build.
- [x] (2026-03-06 14:58Z) Reworked the Whisper hotkey path so rolling updates are popup-only, preserved the last popup text during the release-time batch decode, and restored one final paste on completion from the batch transcript.
- [ ] Run manual in-app verification for popup-only live preview, single final paste, and preserved non-Whisper/manual flows.

## Surprises & Discoveries

- Observation: the current external text insertion path is entirely clipboard-driven, using one `Cmd+V` and restoring the pasteboard immediately afterward.
  Evidence: `OpenSuperWhisper/Utils/ClipboardUtil.swift` only exposes pasteboard-backed insertion helpers.

- Observation: the repo already bridges `whisper_full` segment callbacks even though the app does not use them today.
  Evidence: `OpenSuperWhisper/Whis/WhisperFullParams.swift` defines `newSegmentCallback`, and `OpenSuperWhisper/Whis/Whis.swift` maps it into `whisper_full_params`.

- Observation: modifier-only hotkeys make repeated `Cmd+V` during the hold window unsafe because the pressed modifier key remains physically down.
  Evidence: `OpenSuperWhisper/ModifierKeyMonitor.swift` tracks key state from `flagsChanged`, so the held modifier remains active until release.

- Observation: `xcodebuild` ignores workspace-local SwiftPM checkout patches unless it is pointed at `SourcePackages` with `-clonedSourcePackagesDirPath SourcePackages`.
  Evidence: the first validation build compiled `FluidAudio` from `~/Library/Developer/Xcode/DerivedData/.../SourcePackages/...` and hit Swift concurrency errors there; the succeeding validation build used `-clonedSourcePackagesDirPath SourcePackages` and picked up the local compatibility patch.

- Observation: the new AX helper code needed stricter Core Foundation casting on the current SDK than older project code paths used.
  Evidence: the first app-target build failed in `OpenSuperWhisper/Utils/FocusUtils.swift` on conditional casts to `AXValue` and on passing an immutable `CFRange` as `inout`.

- Observation: segment end times alone were not stable enough to deduplicate rolling Whisper updates; overlapping decodes could re-emit the same phrase with slightly shifted boundaries and cause repeated insertion.
  Evidence: manual live testing produced repeated transcript blocks such as “Okay, this is a streaming test...” multiple times even though only one phrase was spoken; regression tests now cover shifted-boundary overlap cases in `OpenSuperWhisperTests/OpenSuperWhisperTests.swift`.

- Observation: the local Whisper bridge already had token-level timestamps, but the live sample transcription path was not enabling or extracting them, so the accumulator had no stable boundary finer than a whole segment.
  Evidence: `OpenSuperWhisper/Whis/Whis.swift` exposes `fullNTokens`, `fullGetTokenText`, and `fullGetTokenData`, while `OpenSuperWhisper/Whis/WhisperFullParams.swift` exposes `tokenTimestamps`; the merged-prefix repetition persisted until `WhisperEngine.transcribeSamples` started requesting and returning timed tokens.

- Observation: some target apps do not leave the AX selected range at the end of the text after a whole-value write, so reading the range fresh on each live delta can prepend the next chunk back at the original caret position.
  Evidence: manual testing after the token dedup fix produced correctly deduplicated chunks inserted at the start of the field; `FocusedTextInsertionSession` now keeps the insertion range locally and feeds it back into each subsequent AX write.

- Observation: raw Whisper token timestamps are still subword-level, so committing them directly creates artifacts like duplicated boundary words or partial-word outputs such as `halluc hallucinations`.
  Evidence: live testing after the first token-timestamp fix produced subword-style artifacts in the external text field even though the rolling prefix duplication was reduced; the accumulator now defers trailing token text until it reaches a safe word boundary.

- Observation: even after range-tracking and sanitizer fixes, exposing rolling Whisper chunks directly to third-party text fields still leaked model instability and spacing artifacts that were acceptable in a popup preview but too noisy for the final inserted text.
  Evidence: user reports showed the early `follow-up changes` phrase and collapsed-word boundaries in the target app even when the live popup path was improving; the fix was to make live updates popup-only and use the final batch transcript as the single insertion source of truth.

## Decision Log

- Decision: v1 will be Whisper-only for live streaming and will leave FluidAudio on the existing batch path.
  Rationale: Whisper already exists in the hotkey path and can be extended without replacing the app’s engine abstraction in one step.
  Date/Author: 2026-03-06 / Codex

- Decision: v1 will insert only confirmed text into the focused external field and keep unstable text as preview-only inside the app.
  Rationale: tiny or unstable hypotheses are too error-prone to commit into arbitrary third-party text fields without rewrite support.
  Date/Author: 2026-03-06 / Codex

- Decision: unsupported or unsafe focused fields will use a release-time buffered paste fallback instead of repeated paste attempts while the hotkey is held.
  Rationale: modifier leakage and focus churn make repeated paste unreliable during a hold-to-record session.
  Date/Author: 2026-03-06 / Codex

- Decision: validation will use `xcodebuild ... -clonedSourcePackagesDirPath SourcePackages` for this workspace.
  Rationale: the local Xcode beta toolchain needs a compatibility patch in the gitignored `SourcePackages` checkout, and the default DerivedData checkout does not see that patch.
  Date/Author: 2026-03-06 / Codex

- Decision: live deduplication will use both a decode window anchored to `lastCommittedEndTime - overlapSeconds` and textual suffix/prefix overlap stripping, rather than relying only on segment `endTime > lastCommittedEndTime`.
  Rationale: Whisper can merge or shift segment boundaries between rolling decodes; timestamp-only filtering was allowing repeated committed and preview text through.
  Date/Author: 2026-03-06 / Codex

- Decision: the live accumulator will prefer token-level commit boundaries whenever the engine returns timed tokens, with the previous segment-based path preserved as the fallback for batch callers and tests that do not provide token payloads.
  Rationale: segment timing can shift enough to drag an entire already-committed prefix back into the next rolling decode, while token timings let the session commit only the words that actually crossed the stability boundary.
  Date/Author: 2026-03-06 / Codex

- Decision: live transcript assembly will strip Whisper control markers such as `[_BEG_]` / `[_TT_191]` and the known silence hallucination phrase “Ask for follow-up changes” before external insertion.
  Rationale: these artifacts are not user speech and should never leak into external text fields even if Whisper emits them during unstable or silent windows.
  Date/Author: 2026-03-06 / Codex

- Decision: token-backed live updates will allow one-word suffix/prefix overlap removal and will only commit through the last safe word boundary, leaving trailing subword fragments in preview until they stabilize.
  Rationale: token timestamps solve merged-prefix replay, but Whisper tokens are not whole words; without an extra boundary rule the app still leaks repeated last words and partial subword artifacts into committed text.
  Date/Author: 2026-03-06 / Codex

- Decision: live Whisper text will no longer be inserted into external apps while the hotkey is held; only the popup streams live, and the target app receives one final paste from the full-file batch decode after key release.
  Rationale: popup preview tolerates instability, but external text fields need one accurate source of truth. This removes the early hallucination and missing-space failure modes from the user-visible inserted text without sacrificing fast feedback in the popup.
  Date/Author: 2026-03-06 / Codex

## Outcomes & Retrospective

The implementation now provides a Whisper-only live hotkey session that captures 16 kHz PCM while the key is held, performs rolling decodes, and streams stable-plus-preview text only inside the popup. On key release, the recorder stops, the popup keeps the last live text visible while one full-file batch Whisper pass runs, and the target app plus saved recording/history entry both use that single final batch transcript. The post-implementation dedup fix now requests token timestamps from Whisper and commits popup text by token edge instead of by merged segment edge, which removes the repeated-prefix failure mode seen in rolling decodes that restarted from `00:00:00.000`.

Automated coverage was added for the rolling commit accumulator and insertion fallback buffer, and both the focused tests and a full scheme build pass succeeded in this workspace. Manual app verification remains for the next session because it requires interactive use in TextEdit and another target app with changing focus.

## Context and Orientation

`OpenSuperWhisper/ShortcutManager.swift` owns the hotkey lifecycle. `handleKeyDown()` starts recording and `handleKeyUp()` stops recording only for hold-to-record mode after the threshold is crossed. `OpenSuperWhisper/Indicator/IndicatorWindow.swift` owns the mini indicator state and currently calls `TranscriptionService.transcribeAudio(url:settings:)` only after recording stops. `OpenSuperWhisper/AudioRecorder.swift` currently records through `AVAudioRecorder`, writes a temporary WAV file, and exposes `startRecording()` / `stopRecording()`.

`OpenSuperWhisper/TranscriptionService.swift` is the app-level coordinator for engine loading and batch transcription state. `OpenSuperWhisper/Engines/WhisperEngine.swift` already converts audio to 16 kHz PCM and runs `whisper_full`, but it only returns a final string. `OpenSuperWhisper/Utils/ClipboardUtil.swift` inserts text into other apps by replacing the pasteboard and simulating `Cmd+V`. `OpenSuperWhisper/Utils/FocusUtils.swift` already reads the focused accessibility element and caret position, but it does not write text.

In this plan, “confirmed text” means text from segments that end far enough behind the live edge to be treated as stable. “Preview tail” means unstable trailing text shown in the app but not yet inserted into the external field. “Fallback insertion” means buffering confirmed text and using the existing paste path once the hotkey is released because the field is not safely writable through accessibility APIs.

## Plan of Work

First, extend `OpenSuperWhisper/AudioRecorder.swift` with a second capture mode for hotkey streaming that uses `AVAudioEngine` with an input tap. This path must write the same session to disk through `AVAudioFile` while also resampling incoming PCM to 16 kHz mono floats and delivering those samples through a callback. It must not disturb the existing `AVAudioRecorder` path used by manual recordings and current batch callers.

Second, extend `OpenSuperWhisper/Engines/WhisperEngine.swift` with a sample-based entrypoint that takes `[Float]` PCM, runs Whisper over that sample buffer, and returns timestamped segments. Keep the current file-based `transcribeAudio(url:settings:)` implementation in place for the manual path and the final saved-recording pass.

Third, add live-session orchestration in `OpenSuperWhisper/TranscriptionService.swift`. The live session must own the rolling sample buffer, decode cadence, overlap logic, last committed boundary, preview tail, and final flush. The v1 constants are fixed in code: 2.0 seconds warmup, 1.5 seconds decode cadence, 12.0 seconds rolling window, 2.0 seconds overlap before the committed boundary, and a 1.5 second stability buffer. Segments ending at or before `liveEdge - 1.5 seconds` and after `lastCommittedEnd` become committed text. Newer text becomes preview only.

Fourth, add an accessibility-based text insertion helper under `OpenSuperWhisper/Utils`. At session start it must snapshot the frontmost application and the focused text element. While the session remains valid, each committed delta should append to that same field through accessibility APIs. If the field cannot be written, or the focus/app changes, the helper must stop live insertion, buffer remaining committed text, and hand it back for one final release-time paste through `ClipboardUtil`.

Fifth, rewire `OpenSuperWhisper/Indicator/IndicatorWindow.swift` and `OpenSuperWhisper/ShortcutManager.swift` so Whisper hold-to-record starts a live session on key down, updates the indicator using `TranscriptionService.transcribedText` and `currentSegment`, and finalizes on key up. On release, the recorder stops, the session flushes the tail, buffered fallback text is inserted if needed, and one background batch Whisper pass stores the final recording/history entry.

Finally, add focused tests for the rolling commit logic, punctuation/spacing across committed deltas, and insertion fallback behavior. Then run targeted Xcode tests and a build to confirm the feature compiles and the existing flows remain intact.

## Concrete Steps

From the repository root:

    xcodebuild -list -project OpenSuperWhisper.xcodeproj

Expected result: the `OpenSuperWhisper` scheme is available.

During implementation, use targeted commands such as:

    xcodebuild test -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:OpenSuperWhisperTests/LiveTranscriptionAccumulatorTests -only-testing:OpenSuperWhisperTests/BufferedTextInsertionStateTests

and

    xcodebuild build -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

Actual validation commands used:

    xcodebuild build -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet

Expected/observed result: build succeeds. In this workspace the linker emits one warning about `@rpath/libomp.dylib` being built for macOS 26.0 while the app target is macOS 14.0.

    xcodebuild test -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:OpenSuperWhisperTests/LiveTranscriptionAccumulatorTests -only-testing:OpenSuperWhisperTests/BufferedTextInsertionStateTests -quiet

Expected/observed result: both targeted test suites pass.

## Validation and Acceptance

Acceptance requires both automated and manual proof:

Run targeted unit tests for rolling commit logic and fallback insertion helpers. The new tests should prove that overlapping decodes do not duplicate committed text, that preview text never becomes committed too early, and that unsupported focused fields buffer for release-time insertion instead of attempting repeated live paste.

Then launch the app, select the Whisper engine, and hold the hotkey inside TextEdit for at least five seconds. Stable text should begin appearing after the initial warmup while the key is still held. Releasing the key should flush the final tail, close the session cleanly, and add a completed recording entry to history. The manual recording button and FluidAudio engine should still behave exactly as before.

## Idempotence and Recovery

The source edits are additive and can be applied incrementally. If live insertion fails for a field, the session must fall back to buffering and release-time paste rather than leaving the app in a half-inserted state. If the live session is cancelled or the hotkey flow is interrupted, the recorder should stop the input tap, close the temporary file, and reset indicator/session state without affecting the manual recording path.

## Artifacts and Notes

Add concise validation transcripts here as implementation proceeds, including any failing tests discovered and the final build/test outputs used to confirm the feature.

    Testing started
    Test suite 'BufferedTextInsertionStateTests' started on 'My Mac - OpenSuperWhisper (...)'
    Test case 'BufferedTextInsertionStateTests.testRecordCommittedDelta_buffersWhenLiveInsertionFailsAndFinalizesOnce()' passed
    Test case 'BufferedTextInsertionStateTests.testRecordCommittedDelta_noopForEmptyText()' passed
    Test suite 'LiveTranscriptionAccumulatorTests' started on 'My Mac - OpenSuperWhisper (...)'
    Test case 'LiveTranscriptionAccumulatorTests.testApply_addSpaceAfterSentence_onlyTouchesCommittedDelta()' passed
    Test case 'LiveTranscriptionAccumulatorTests.testApply_commitsOnlyStableSegmentsAndKeepsTailAsPreview()' passed
    Test case 'LiveTranscriptionAccumulatorTests.testApply_skipsCommittedOverlapAndFlushesTailOnFinal()' passed

    /Users/axel/Desktop/Code_Projects/Personal/Whisper/OpenSuperWhisper.xcodeproj: OpenSuperWhisper: ld: warning: building for macOS-14.0, but linking with dylib '@rpath/libomp.dylib' which was built for newer version 26.0

## Interfaces and Dependencies

The implementation must add the following Swift interfaces or equivalent shapes:

    struct LiveTranscriptionUpdate {
        let committedText: String
        let committedDelta: String
        let previewTail: String
        let committedEndTime: Double
        let isFinal: Bool
    }

    struct WhisperSegmentResult {
        let text: String
        let startTime: Double
        let endTime: Double
    }

`OpenSuperWhisper/AudioRecorder.swift` must expose live hotkey capture APIs alongside the existing batch recording APIs:

    func startLiveHotkeyCapture(onSamples: @escaping @Sendable ([Float]) -> Void)
    func stopLiveHotkeyCapture() -> URL?

`OpenSuperWhisper/Engines/WhisperEngine.swift` must expose:

    func transcribeSamples(_ samples: [Float], settings: Settings) async throws -> [WhisperSegmentResult]

`OpenSuperWhisper/TranscriptionService.swift` must own the live-session actor and expose start/consume/finish helpers for the hotkey flow while preserving `transcribeAudio(url:settings:)` for existing callers.

Revision note: created from the approved design plan so implementation can proceed in-repo with the required living ExecPlan structure.

Revision note: updated after implementation and validation to record the concrete files changed, the `-clonedSourcePackagesDirPath SourcePackages` validation requirement for this workspace, and the automated test/build evidence.

Revision note: updated after a post-implementation bug fix to record the rolling deduplication strategy change and the new shifted-boundary regression coverage.

Revision note: updated after the second live-streaming bug fix to record the move to token-based deduplication, the live `tokenTimestamps` engine wiring, and the merged-prefix regression test coverage.

Revision note: updated after the follow-up live-streaming fix to record the session-owned AX insertion range, the transcript artifact sanitization, and the new insertion/sanitization regression tests.

Revision note: updated after the next live-streaming refinement to record the safe word-boundary token commit rule, the single-word token overlap handling, and the relaxed AX focused-element targeting.

Revision note: updated after the popup-only follow-up refinement to record that live Whisper streaming now stays inside the popup, the live branch preserves the last preview while the final batch decode runs, and the target app receives only the final batch transcript once on release.
