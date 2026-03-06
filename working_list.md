# Working List

## Pending
- [ ] Run manual in-app verification for live streaming behavior and fallback insertion

## In Progress
- [~] Verify the live insertion-range fix and transcript sanitization changes in-app

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
