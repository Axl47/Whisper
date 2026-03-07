# Working List

## Pending
- [ ] Run manual in-app verification for popup-only live preview and single final paste
- [ ] Run manual in-app verification for the Liquid Glass overlay on the live indicator

## In Progress
- [ ] No active implementation task

## Done
- [x] Review the existing hotkey, recorder, transcription, and insertion flows
- [x] Create execution artifacts and seed the implementation plan
- [x] Implement live hotkey capture in `OpenSuperWhisper/AudioRecorder.swift`
- [x] Implement focused text insertion fallback in `OpenSuperWhisper/Utils`
- [x] Implement rolling Whisper live session in `OpenSuperWhisper/TranscriptionService.swift`
- [x] Wire hotkey indicator flow to live streaming and finalize-on-release
- [x] Add automated tests for rolling commit and fallback insertion behavior
- [x] Run targeted validation for build and tests
- [x] Update `AGENTS.md` with surprising implementation notes
- [x] Enable token timestamps for live Whisper decoding and extract timed tokens
- [x] Move the live accumulator from segment-level commit boundaries to token-level commit boundaries
- [x] Validate the token-based live dedup fix with targeted tests and a local build
- [x] Preserve the live insertion range across AX appends so later chunks stay at the caret tail
- [x] Strip Whisper control tokens and the known silence hallucination phrase from live transcript assembly
- [x] Commit live token output only at safe word boundaries to avoid partial-word artifacts and single-word overlap repeats
- [x] Refactor the Whisper hotkey flow so rolling updates stay inside the popup and the app receives one final paste from the batch transcript
- [x] Preserve the last popup preview while the post-release batch decode runs
- [x] Add popup preview boundary-formatting coverage and re-run focused tests plus a full build
- [x] Update the living docs for the popup-only live preview behavior
- [x] Refine the indicator UI so the transcript sits in a separated container and the panel resizes with live text
- [x] Refresh the indicator overlay to a subtle Liquid Glass style with native glass on supported macOS versions and a matched material fallback
- [x] Deepen the Liquid Glass styling so the status row and transcript background share the same stronger glass surface language
- [x] Simplify the overlay hierarchy so the indicator reads as one HUD surface instead of stacked glass boxes
- [x] Remove the transcript panel highlight artifact that created a broken glossy patch at the top-left
