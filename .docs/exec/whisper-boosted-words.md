# Whisper-Only Boosted Words

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

After this change, users can give the Whisper engine a list of preferred spellings for names, jargon, and domain-specific phrases. The app will bias Whisper toward those spellings during decode time in both normal Whisper transcription and the live Whisper hotkey flow. This does not retrain the model or permanently teach pronunciation; it is a conservative decode-time preference layer.

Users should see a new Whisper-only `Boosted Words` settings card with one phrase per line. When it is empty, Whisper behaves exactly as before. When it has entries, those preferred spellings are more likely to appear in both the live Whisper overlay and the final transcript.

## Progress

- [x] (2026-03-11 19:15Z) Grounded the design against the current Whisper bridge, settings flow, and `whisper.cpp` decode hooks.
- [x] (2026-03-11 19:15Z) Created the ExecPlan and working list artifacts for this implementation.
- [x] (2026-03-11 19:20Z) Implemented the boosted-words parsing, compilation, and biasing helper in `OpenSuperWhisper/Engines/WhisperBoostedWords.swift`.
- [x] (2026-03-11 19:20Z) Threaded the persisted boosted-words setting through `AppPreferences`, `Settings`, and the Whisper-only settings UI.
- [x] (2026-03-11 19:20Z) Wired the Whisper decode callback in `OpenSuperWhisper/Engines/WhisperEngine.swift` for both batch and live Whisper paths.
- [x] (2026-03-11 19:20Z) Added focused unit tests for parser, compiler, bias behavior, and preference round-tripping in `OpenSuperWhisperTests/WhisperBoostedWordsTests.swift`.
- [x] (2026-03-11 19:20Z) Updated `AGENTS.md` with the new boosted-words debugging note.
- [x] (2026-03-11 19:20Z) Ran focused tests and a full app build to validate the change.
- [ ] Perform manual in-app verification for Whisper-only UI visibility and glossary behavior.

## Surprises & Discoveries

- Observation: the repo already exposes the strongest needed hook through `whisper_logits_filter_callback`.
  Evidence: `OpenSuperWhisper/Whis/WhisperFullParams.swift` already bridges `logitsFilterCallback`, and `libwhisper/whisper.cpp/src/whisper.cpp` applies it during token decode.

- Observation: the app already has a weaker text-level steering mechanism in the existing `initialPrompt` setting.
  Evidence: `OpenSuperWhisper/Utils/AppPreferences.swift`, `OpenSuperWhisper/Settings.swift`, and `OpenSuperWhisper/Engines/WhisperEngine.swift` thread `initialPrompt` into `WhisperFullParams.initialPrompt`.

- Observation: the Xcode project uses filesystem-synchronized groups, so new Swift source and test files do not need `project.pbxproj` edits.
  Evidence: `OpenSuperWhisper.xcodeproj/project.pbxproj` contains `PBXFileSystemSynchronizedRootGroup` entries for both `OpenSuperWhisper` and `OpenSuperWhisperTests`.

- Observation: one-token glossary entries still need token-history awareness in the callback, otherwise they look like sentence-start candidates on every decode step.
  Evidence: the callback now keeps at least one recent token ID even when `maxSequenceLength == 1`, while continuation boosting still short-circuits for single-token entries.

## Decision Log

- Decision: v1 will be Whisper-only and will not affect the Parakeet/FluidAudio engine.
  Rationale: the user requested Whisper-only behavior, and the current engine abstraction already separates Whisper and FluidAudio paths.
  Date/Author: 2026-03-11 / Codex

- Decision: the glossary will apply to both batch Whisper transcription and the live Whisper hotkey path.
  Rationale: both flows already route through `WhisperEngine.runSampleTranscription`, so shared behavior is low-risk and keeps live/final transcripts consistent.
  Date/Author: 2026-03-11 / Codex

- Decision: v1 will use a conservative additive bias model with fixed strengths and no token suppression.
  Rationale: the goal is to nudge spelling, not force hard vocabulary constraints that would increase hallucinations.
  Date/Author: 2026-03-11 / Codex

- Decision: persisted storage will be a raw multiline string with one phrase per line.
  Rationale: this matches the requested UI, avoids migrations, and keeps the settings surface simple.
  Date/Author: 2026-03-11 / Codex

## Outcomes & Retrospective

The feature now exists as a Whisper-only decode-time glossary. Users can enter one preferred word or phrase per line in the new `Boosted Words` settings card, and Whisper applies conservative token-level boosts during both file transcription and live Whisper preview/finalization. The implementation kept the existing `Initial Prompt` setting separate, left the Parakeet/FluidAudio engine untouched, and treated an empty glossary as a complete no-op.

Focused tests and a full app build passed in this workspace. Manual app verification remains for the next interactive session because it requires listening and comparing real Whisper transcription behavior with and without glossary entries configured. The most likely follow-up extension, if needed later, is a spoken-alias layer or per-language glossaries built on top of this token compilation path.

## Context and Orientation

`OpenSuperWhisper/Utils/AppPreferences.swift` stores persisted engine and transcription preferences. `OpenSuperWhisper/Settings.swift` contains both the `SettingsViewModel` that mirrors those preferences into SwiftUI state and the `Settings` value type used by transcription calls.

`OpenSuperWhisper/Engines/WhisperEngine.swift` is the single Whisper implementation used for both file transcription and the live Whisper hotkey flow. Both `transcribeAudio(url:settings:)` and `transcribeSamples(_:settings:)` route through `runSampleTranscription`, which makes it the correct place to install a decode-time bias callback.

`OpenSuperWhisper/Whis/WhisperFullParams.swift` bridges `whisper_full_params`, including `logitsFilterCallback` and `logitsFilterCallbackUserData`. `OpenSuperWhisper/Whis/Whis.swift` exposes tokenization and token-to-string helpers that can be reused to compile user-entered phrases into Whisper token sequences.

In this plan, “root boost” means a small additive logit increase when a configured phrase begins at a valid word boundary. “Continuation boost” means a stronger additive logit increase once the already-decoded token history matches the prefix of a configured phrase.

## Plan of Work

First, add a new pure-Swift helper file at `OpenSuperWhisper/Engines/WhisperBoostedWords.swift`. It will parse the multiline settings string, tokenize phrases through an injected tokenizer closure, compile both exact-start and `" " + phrase` variants, and store the result in an immutable model. The helper will also provide a biaser that takes recent decoded token IDs plus the last token text to decide which candidate next tokens should receive conservative boosts.

Second, thread the raw multiline setting through `AppPreferences`, `SettingsViewModel`, and `Settings`, then add a Whisper-only settings card in `OpenSuperWhisper/Settings.swift`. This card will stay separate from `Initial Prompt`, use a `TextEditor`, and explain that the feature biases spelling but does not train the model.

Third, extend `OpenSuperWhisper/Engines/WhisperEngine.swift` so each decode call attempts to compile the boosted-word model from the current settings. If compilation yields a non-empty model, create a short-lived callback context, set `logitsFilterCallback` and `logitsFilterCallbackUserData`, and let `whisper_full` invoke that callback during batch and live decoding. If compilation fails or the glossary is empty, leave the callback unset and continue normally.

Fourth, add focused unit tests in `OpenSuperWhisperTests/WhisperBoostedWordsTests.swift` for parsing, compilation with a stub tokenizer, boundary-sensitive root boosts, continuation boosts, max-not-sum behavior, empty glossary behavior, and `AppPreferences` round-tripping.

Finally, update `AGENTS.md` with a note explaining where boosted-word biasing lives and how to debug over-insertion issues, then run targeted tests and an app build.

## Concrete Steps

From the repository root:

    xcodebuild test -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:OpenSuperWhisperTests/WhisperBoostedWordsTests -only-testing:OpenSuperWhisperTests/VoiceWorkflowPersistenceTests -quiet

Expected result: the new focused tests plus the existing preference persistence test pass.

Then run:

    xcodebuild build -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet

Expected result: the app target builds successfully in this workspace.

## Validation and Acceptance

Automated validation requires focused unit tests proving the parser, compiler, and biaser behavior, plus a build that confirms the new callback hook compiles with the existing Whisper bridge.

Manual acceptance requires launching the app, switching to the Whisper engine, and confirming the new `Boosted Words` card appears only for Whisper. Enter a distinctive term such as `Kubernetes`, transcribe speech that previously tended to misspell it, and verify that both the live Whisper overlay and the final Whisper transcript are more likely to emit `Kubernetes`. Switch to Parakeet and confirm the card is hidden and the glossary has no effect there. Clear the glossary and confirm Whisper returns to baseline behavior.

## Idempotence and Recovery

The new persisted setting defaults to an empty string, so the feature is effectively off until configured. If tokenization or model compilation fails for any phrase, the engine must ignore that phrase and proceed without crashing or blocking transcription. The callback object must live only for the duration of the synchronous `whisper_full` call and must not introduce shared mutable state across transcriptions.

## Artifacts and Notes

Validation commands used in this workspace:

    xcodebuild test -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:OpenSuperWhisperTests/WhisperBoostedWordsTests -only-testing:OpenSuperWhisperTests/VoiceWorkflowPersistenceTests -quiet

Observed result: the four existing `VoiceWorkflowPersistenceTests` passed, and the seven new `WhisperBoostedWordsTests` passed.

    xcodebuild build -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet

Observed result: the app build succeeded. The workspace still emits the pre-existing linker warning about `@rpath/libomp.dylib` being built for macOS 26.0 while the app target is macOS 14.0.

## Interfaces and Dependencies

The implementation must add the following internal interfaces or equivalent shapes:

    enum WhisperBoostPreset {
        case conservative
    }

    struct WhisperBoostedWordsModel {
        let startVariants: [WhisperTokenSequence]
        let spacedVariants: [WhisperTokenSequence]
        let continuationTrie: WhisperBoostTrieNode
        let maxSequenceLength: Int
        let preset: WhisperBoostPreset
    }

    enum WhisperBoostedWordsParser {
        static func parse(_ rawValue: String) -> [String]
    }

    struct WhisperBoostedWordsCompiler {
        let tokenize: (String) -> [WhisperToken]
        func compile(rawValue: String, preset: WhisperBoostPreset) -> WhisperBoostedWordsModel?
    }

    struct WhisperBoostedWordsBiaser {
        static func boosts(
            for recentTokens: [WhisperToken],
            lastTokenText: String?,
            model: WhisperBoostedWordsModel
        ) -> [WhisperToken: Float]
    }

Revision note: created from the approved plan before implementation so the feature work stays documented in-repo.

Revision note: updated after implementation to record the completed code paths, the single-token callback boundary discovery, and the focused test/build validation evidence.
