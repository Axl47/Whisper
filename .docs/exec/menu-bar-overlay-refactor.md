# Menu-Bar Overlay Refactor For OpenSuperWhisper

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with [.docs/PLANS.md](.docs/PLANS.md).

## Purpose / Big Picture

After this change, OpenSuperWhisper no longer opens into a fixed-width main window after onboarding. Instead, it behaves like a menu-bar app: the status item is always present, clicking `OpenSuperWhisper` opens a floating Liquid Glass overlay, and that overlay becomes the primary surface for transcript search, recent history, and recording controls. The search field also becomes a command-bar style entry point that still searches transcripts by default but can switch into a lightweight quick-action mode with a leading `>`.

The user should be able to verify the change by launching the app after onboarding is complete and observing that no standard window appears, only the menu-bar item. Choosing `OpenSuperWhisper` from the menu should present a centered overlay near the top of the screen, focus the command bar, preserve existing recording/history behavior, and allow settings and onboarding to open in separate windows.

## Progress

- [x] (2026-03-08 23:33Z) Re-read the relevant repository files and the Nexus overlay reference before implementation.
- [x] (2026-03-08 23:33Z) Lock the product decisions for overlay scope, quick-action scope, settings window behavior, and onboarding separation.
- [x] (2026-03-08 23:40Z) Create the new app lifecycle split with a dedicated app delegate, overlay panel controller, and onboarding window controller.
- [x] (2026-03-08 23:44Z) Extract reusable content sections from `OpenSuperWhisper/ContentView.swift` and compose them inside a new `MainOverlayView`.
- [x] (2026-03-08 23:45Z) Replace the old search row with a command-bar implementation that supports transcript search plus `>` quick actions.
- [x] (2026-03-08 23:45Z) Rewire menu, file-open, settings, and onboarding flows so the app launches menu-bar-only after onboarding and only shows the overlay on explicit open.
- [x] (2026-03-08 23:48Z) Run a successful app build after the refactor and record the remaining manual validation items.
- [ ] Manually verify overlay keyboard navigation, quick actions, and first-run/onboarding behavior in the running app.

## Surprises & Discoveries

- Observation: The project uses `PBXFileSystemSynchronizedRootGroup` entries in `OpenSuperWhisper.xcodeproj/project.pbxproj`, so adding files inside the app folder hierarchy does not require hand-editing build file lists in the project file.
  Evidence: `grep -n "PBXFileSystemSynchronizedRootGroup" OpenSuperWhisper.xcodeproj/project.pbxproj`

- Observation: `OnboardingView` only depends on `AppState` to flip `hasCompletedOnboarding` to `true`, so onboarding can be moved out of the main `WindowGroup` into a dedicated AppKit-hosted window without changing the actual onboarding content.
  Evidence: `OpenSuperWhisper/Onboarding/OnboardingView.swift` references `@EnvironmentObject private var appState: AppState` and sets `appState.hasCompletedOnboarding = true` on continue.

- Observation: The repository already defines a model type named `Settings`, which shadows SwiftUI’s `Settings` scene name. The app entrypoint must explicitly use `SwiftUI.Settings` once the main window scene is removed.
  Evidence: `OpenSuperWhisper/OpenSuperWhisperApp.swift` failed to compile until the settings scene was qualified as `SwiftUI.Settings`.

- Observation: `xcodebuild ... build` succeeds for the app target after the refactor, but existing warnings remain in `libwhisper` and `OpenSuperWhisper/Workflows/LiveRecordingCoordinator.swift`.
  Evidence: `xcodebuild -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build`

## Decision Log

- Decision: Keep the existing AppKit `NSStatusItem` menu instead of migrating to `MenuBarExtra`.
  Rationale: The status menu already owns language and microphone selection. Reusing it keeps the refactor focused on replacing the main window with an overlay instead of rewriting the menu-bar entrypoint.
  Date/Author: 2026-03-08 / Codex

- Decision: Host the primary overlay with an AppKit `NSPanel` and host onboarding in a separate AppKit-managed window.
  Rationale: This avoids SwiftUI scene auto-opening behavior that would otherwise recreate a main window. It also gives explicit control over accessory-mode launch, dismissal-on-resign behavior, and centered positioning.
  Date/Author: 2026-03-08 / Codex

- Decision: Keep settings in the SwiftUI `Settings` scene and open them through the standard `showSettingsWindow:` action.
  Rationale: The settings content already exists as `SettingsView` and does not need to live inside the new overlay. Using the built-in settings scene minimizes churn while satisfying the separate-window requirement.
  Date/Author: 2026-03-08 / Codex

- Decision: Keep `ContentViewModel`, `RecordingRow`, and the existing queue notifications intact, and only refactor the container views around them.
  Rationale: This preserves current recording, pagination, workflow row, and transcription-finalization behavior while replacing the primary surface and search affordance.
  Date/Author: 2026-03-08 / Codex

- Decision: Treat search-result activation from the new command bar as “copy the selected transcription to the pasteboard and close the overlay.”
  Rationale: The old main window had no row activation concept. Copying the transcript is the most useful keyboard action that matches a command-palette-style overlay without inventing a second detail view.
  Date/Author: 2026-03-08 / Codex

## Outcomes & Retrospective

The main refactor is complete. The app now launches without a standard main window, the status-item menu opens an AppKit-managed overlay, onboarding is a separate AppKit window, and settings remain a separate SwiftUI settings window. The remaining gap is manual interaction validation: the build is green, but the overlay’s keyboard and first-run flows still need in-app human verification.

## Context and Orientation

`OpenSuperWhisper/OpenSuperWhisperApp.swift` is currently both the SwiftUI app entrypoint and the home of `AppDelegate`. Today it creates one `WindowGroup` that shows `OnboardingView` before first-run completion and `ContentView` afterward. That is the behavior being removed for everyday use.

`OpenSuperWhisper/ContentView.swift` contains both the main view model (`ContentViewModel`) and nearly all of the existing main-window UI. It already owns transcript search, the recordings list, the record button, queue/list refresh notifications, and the loading overlay. The plan is to preserve `ContentViewModel` and row-level components but move the layout into reusable sections that can be hosted inside the new overlay.

`OpenSuperWhisper/Indicator/IndicatorWindow.swift` already contains the app’s Liquid Glass visual language, including the macOS 26 `glassEffect` branch and the fallback material-based branch. The new overlay should reuse this look instead of inventing a separate blur style.

`OpenSuperWhisper/Settings.swift` already defines `SettingsView`, and `OpenSuperWhisper/Onboarding/OnboardingView.swift` already defines the onboarding flow. They remain separate surfaces in the finished app, but they are no longer children of the old main `WindowGroup`.

The Nexus reference lives outside this repository under `~/Desktop/Code_Projects/Personal/Nexus/Nexus/Views/Overlay/`. The useful parts are `OverlayPanel.swift` and `OverlayPanelController.swift`, which demonstrate a small `NSPanel` subclass that can become key, dismiss on resign, and center near the top of the active screen.

In this repository, “overlay” means a focusable floating panel presented by AppKit, not a standard resizable app window. “Command bar” means the overlay’s search field now handles both transcript search and a small set of quick actions prefixed by `>`. “Quick actions” are local app actions such as starting recording, stopping recording, opening settings, or clearing search.

## Plan of Work

First, split lifecycle responsibilities out of `OpenSuperWhisper/OpenSuperWhisperApp.swift`. Create a dedicated `OpenSuperWhisper/App/AppDelegate.swift`, move the menu-bar setup and file-open handling there, and replace the old `showMainWindow()` flow with overlay-specific `showOverlay()`, `toggleOverlay()`, and `hideOverlay()` methods. Add a shared `AppState` file so onboarding and the app delegate can coordinate onboarding completion without relying on the old `WindowGroup` root.

Next, add the new AppKit presentation layer under `OpenSuperWhisper/Overlay/`. `MainOverlayPanel.swift` should mirror the Nexus key-panel pattern, `MainOverlayPanelController.swift` should build and position the panel, and `MainOverlayView.swift` should become the SwiftUI root view hosted by the panel. Create a small onboarding window controller alongside it so first launch can still show onboarding even though the normal app now runs as an accessory-only menu-bar app.

Then refactor `OpenSuperWhisper/ContentView.swift` into reusable sections. Keep `ContentViewModel`, `RecordingRow`, `PermissionsView`, `MainRecordButton`, and the existing notification-driven refresh logic, but introduce reusable sections for the permissions gate, history list, footer controls, and record controls. Those sections should be designed to work inside the new overlay instead of assuming a narrow document window or a settings sheet.

After that, add the command bar. Create `OpenSuperWhisper/Overlay/OverlayCommandBar.swift` with an `NSTextField`-backed input so arrow keys, enter, and escape can be captured predictably. Plain text should continue using the existing debounced recording search. A leading `>` should switch into quick-action mode and show a small set of actions: record, stop, settings, permissions, clear search, delete all recordings, and open onboarding. The overlay should maintain one selection index shared between quick actions and search results.

Finally, rewire the app scenes and supporting flows. `OpenSuperWhisper/OpenSuperWhisperApp.swift` should stop hosting the old main UI in a primary `WindowGroup`; it should instead create a `Settings` scene, keep the app state alive, and let the app delegate manage the overlay and onboarding windows. Menu actions and file-open events must present the overlay, not a normal window. Onboarding completion must close the onboarding window and switch the app into its normal accessory/menu-bar mode. Update `AGENTS.md` with any non-obvious implementation note that future contributors would need to debug the overlay flow.

## Concrete Steps

From the repository root `/Users/axel/Desktop/Code_Projects/Personal/Whisper`, apply the refactor in this order:

1. Create or update `OpenSuperWhisper/AppState.swift`, `OpenSuperWhisper/App/AppDelegate.swift`, and the overlay/onboarding controller files under `OpenSuperWhisper/Overlay/`.
2. Update `OpenSuperWhisper/OpenSuperWhisperApp.swift` so the app no longer creates the old main `WindowGroup`, but still initializes shared services and exposes a `Settings` scene.
3. Refactor `OpenSuperWhisper/ContentView.swift` into reusable overlay-friendly sections while keeping `ContentViewModel` intact.
4. Add the command-bar view and wire its keyboard callbacks into overlay-local state and quick-action execution.
5. Run targeted validation:

       xcodebuild -project OpenSuperWhisper.xcodeproj \
         -scheme OpenSuperWhisper \
         -destination 'platform=macOS' \
         -clonedSourcePackagesDirPath SourcePackages \
         CODE_SIGNING_ALLOWED=NO \
         CODE_SIGNING_REQUIRED=NO \
         CODE_SIGN_IDENTITY='' \
         test

   If full tests are too expensive or blocked by unrelated toolchain issues, run at minimum a build or the most relevant app target command and document the limitation in this plan and in the final summary.

As implemented on 2026-03-08, the exact successful command was:

       xcodebuild -project OpenSuperWhisper.xcodeproj \
         -scheme OpenSuperWhisper \
         -destination 'platform=macOS' \
         -clonedSourcePackagesDirPath SourcePackages \
         CODE_SIGNING_ALLOWED=NO \
         CODE_SIGNING_REQUIRED=NO \
         CODE_SIGN_IDENTITY='' \
         build

## Validation and Acceptance

Acceptance is behavior-first:

1. Launch the app with onboarding already completed. No standard main window should appear. Only the menu-bar item should be visible.
2. Click `OpenSuperWhisper` from the status-item menu. A top-centered overlay should appear, become key, and focus the command bar.
3. Type plain text into the command bar. The recordings list should filter exactly as the old search field did.
4. Type `>` into the command bar. The overlay should switch into quick-action mode and show the supported local actions.
5. Trigger `>record` and `>stop`. Recording and finalization should still work through `ContentViewModel`.
6. Trigger `>settings`. The separate settings window should open via the app settings scene.
7. Trigger `>open onboarding`. A separate onboarding window should open.
8. Open an audio file with the app or drop one onto the overlay. The overlay should appear and the file should be queued.
9. Press `Esc` with an empty command bar or click outside the overlay while not recording. The overlay should dismiss cleanly.

## Idempotence and Recovery

These changes are additive and can be applied repeatedly. The panel and window controller files can be recreated without harming persisted user data because no schema or file-format migration is involved. If the overlay fails to appear during development, temporarily falling back to `showOverlay()` logging and `NSApp.activate(ignoringOtherApps: true)` is safe; no destructive rollback is required. If the app gets stuck without visible UI during onboarding testing, reset `hasCompletedOnboarding` in `AppPreferences` or launch under a debugger and toggle that value manually.

## Artifacts and Notes

Useful evidence gathered before implementation:

    $ grep -n "PBXFileSystemSynchronizedRootGroup" OpenSuperWhisper.xcodeproj/project.pbxproj
    184:/* Begin PBXFileSystemSynchronizedRootGroup section */

    $ grep -n "hasCompletedOnboarding = true" OpenSuperWhisper/Onboarding/OnboardingView.swift
    482:        appState.hasCompletedOnboarding = true

Useful evidence gathered after implementation:

    $ xcodebuild -project OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
    ** BUILD SUCCEEDED **

## Interfaces and Dependencies

The refactor should end with these repository-level interfaces:

- `OpenSuperWhisper/AppState.swift` defines `@MainActor final class AppState: ObservableObject` with `hasCompletedOnboarding` and helper methods or notifications needed to coordinate onboarding completion.
- `OpenSuperWhisper/App/AppDelegate.swift` defines `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` and public presentation methods `showOverlay()`, `toggleOverlay()`, and `hideOverlay()`.
- `OpenSuperWhisper/Overlay/MainOverlayPanel.swift` defines a small `NSPanel` subclass that can become key and notifies a resign handler.
- `OpenSuperWhisper/Overlay/MainOverlayPanelController.swift` owns the overlay panel lifecycle, frame calculation, dismissal policy, and command-bar focus refresh.
- `OpenSuperWhisper/Overlay/MainOverlayView.swift` is the SwiftUI root of the overlay and composes the extracted sections from `ContentView.swift`.
- `OpenSuperWhisper/Overlay/OverlayCommandBar.swift` defines the command-bar input and quick-action list behavior.

Revision note: Created this ExecPlan at implementation start to capture the locked design and the first implementation decisions before code changes begin.

Revision note: Updated the plan after implementation and successful build validation to record the final architecture, the `SwiftUI.Settings` name-shadowing discovery, and the remaining manual verification work.
