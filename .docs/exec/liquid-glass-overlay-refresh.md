# Liquid Glass Overlay Refresh

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.docs/PLANS.md`.

## Purpose / Big Picture

After this change, the hotkey indicator overlay should look closer to a native modern macOS floating glass surface instead of a darker custom card. Users should still see the same lower-center popup and expanding transcript area, but the panel should feel lighter, more transparent, and more integrated with the desktop backdrop. On newer macOS versions, the overlay should use the system Liquid Glass APIs directly. On older supported macOS versions, it should fall back to a materially similar system-material treatment.

## Progress

- [x] (2026-03-06 15:25Z) Reviewed the existing overlay implementation in `OpenSuperWhisper/Indicator/IndicatorWindow.swift` and the panel positioning logic in `OpenSuperWhisper/Indicator/IndicatorWindowManager.swift`.
- [x] (2026-03-06 15:30Z) Verified the active Xcode beta SDK exposes `GlassEffectContainer` and `glassEffect` on macOS, making an availability-gated native path viable in this workspace.
- [x] (2026-03-06 15:38Z) Reworked `OpenSuperWhisper/Indicator/IndicatorWindow.swift` to use a native Liquid Glass branch on supported macOS versions and a matched material fallback on older targets, while keeping the transcript container visually integrated with the outer surface.
- [x] (2026-03-06 15:43Z) Validated the app target builds with `xcodebuild build ... -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet`.
- [x] (2026-03-06 16:00Z) Strengthened the glass treatment so the status row becomes its own glass badge and the transcript background adopts the same specular highlight / glow language as the outer overlay, then re-ran the full build validation.
- [x] (2026-03-06 16:18Z) Simplified the overlay hierarchy after reviewing the in-app result: removed the full-width status pill, widened the panel, and reduced the number of bordered glass layers so the popup reads as a single HUD with one calmer transcript panel.
- [ ] Run manual in-app verification of the updated overlay appearance in recording and transcribing states.

## Surprises & Discoveries

- Observation: the workspace SDK already supports `GlassEffectContainer(spacing:)` and `.glassEffect(.regular, in: .rect(...))` for macOS, even though the project still targets older deployment versions.
  Evidence: `xcrun swiftc -sdk /Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -target arm64-apple-macos15.0 -typecheck /tmp/liquid_glass_check.swift` succeeded when typechecking those APIs.

- Observation: the indicator layout already cleanly separates content composition from AppKit window sizing, so the visual redesign could stay inside `OpenSuperWhisper/Indicator/IndicatorWindow.swift` without changing resize behavior in `OpenSuperWhisper/Indicator/IndicatorWindowManager.swift`.
  Evidence: the new glass treatment compiled and the existing lower-center positioning / resize behavior remained unchanged during build validation.

- Observation: the first glass pass still read as a lightly frosted card until the status row and transcript background were given the same highlight language as the outer surface.
  Evidence: the follow-up design pass moved the status row into its own glass badge and added shared specular-highlight / ambient-glow overlays to both surfaces in `OpenSuperWhisper/Indicator/IndicatorWindow.swift`.

- Observation: leaning into glass too literally by outlining every subsection produced a “box inside box inside box” look that felt broken instead of premium.
  Evidence: the next pass removed the full-width status capsule and kept only one restrained transcript panel, which simplified the hierarchy in `OpenSuperWhisper/Indicator/IndicatorWindow.swift`.

## Decision Log

- Decision: use native Liquid Glass only behind `#available(macOS 26.0, *)`, with a tuned material fallback for older targets.
  Rationale: the product should adopt the newest system visual language where available, but the repo still supports older macOS versions and needs a coherent fallback instead of a compile-time or runtime fork.
  Date/Author: 2026-03-06 / Codex

- Decision: keep the transcript area as a related inner glass surface with a softened separator instead of collapsing everything into one flat panel.
  Rationale: the user still needs a clear distinction between recording state and transcript preview, but the previous darker inset treatment made the popup feel too boxed and heavy.
  Date/Author: 2026-03-06 / Codex

- Decision: leave panel placement, animation timing, and resize behavior unchanged.
  Rationale: the request is visual, and the recently stabilized lower-center positioning plus dynamic growth behavior should not be risked unless the glass composition required it.
  Date/Author: 2026-03-06 / Codex

- Decision: lean further into the glass treatment by making the status row a distinct glass badge and by giving the transcript background the same highlight and glow language as the outer shell.
  Rationale: a single translucent background was not enough to communicate the intended native glass feel, and the transcript area needed to match that language instead of reading as a plain text box.
  Date/Author: 2026-03-06 / Codex

- Decision: keep the stronger glass materials, but simplify the layout hierarchy to one primary shell, one small status badge, and one restrained transcript panel.
  Rationale: the user-visible problem was not just the colors; the earlier composition had too many nested bordered containers, which made the popup look awkward and heavy.
  Date/Author: 2026-03-06 / Codex

## Outcomes & Retrospective

The overlay now renders as a lighter floating surface with native Liquid Glass on supported macOS versions and a materially similar fallback elsewhere. The transcript section remains separated for readability, but the composition is now simpler: one primary shell, one small badge for the status accessory, and one calmer transcript panel. That removes the previous stacked-box look while preserving the stronger shared glass language introduced in the earlier pass. The implementation stayed intentionally narrow: it changed the look and composition of the popup without affecting recording, transcription, insertion, animation, or panel placement behavior. Manual visual verification remains to confirm the effect feels correct on the running system.

## Context and Orientation

`OpenSuperWhisper/Indicator/IndicatorWindow.swift` defines the SwiftUI view that renders the recording/transcribing popup. This file owns the visible surface styling, status row, and transcript preview section. `OpenSuperWhisper/Indicator/IndicatorWindowManager.swift` is the AppKit bridge that positions and resizes the floating panel; it should only need changes if the popup starts clipping or moving incorrectly.

In this plan, “Liquid Glass” means Apple’s newer system glass presentation APIs exposed through SwiftUI. In practice here, that means `GlassEffectContainer` and the `.glassEffect(...)` modifier. A “fallback” means the alternate look used on older macOS versions that cannot use the native glass APIs. The fallback should still look translucent and restrained, using system materials plus a subtle stroke and shadow.

## Plan of Work

Update `OpenSuperWhisper/Indicator/IndicatorWindow.swift` so the popup surface is composed through two helper layers: an outer glass surface for the whole overlay and an inner related surface for the transcript container. Add availability-gated styling helpers so the native branch uses `GlassEffectContainer` plus `glassEffect` with rounded rectangle geometry, while the fallback branch uses restrained material fills, light strokes, and soft shadows. Preserve the existing status row and transcript content structure, but soften the separator and keep the transcript visually integrated with the main overlay.

Do not change `OpenSuperWhisper/Indicator/IndicatorWindowManager.swift` unless the visual rewrite forces a sizing correction. The lower-center placement and grow-with-content behavior should remain intact from the prior overlay work.

Update `AGENTS.md` after implementation to note that the indicator now has two intentionally matched styling paths. This is important because future UI tweaks need to touch both branches together.

## Concrete Steps

From the repository root `/Users/axel/Desktop/Code_Projects/Personal/Whisper`, inspect the current overlay and plan requirements:

    sed -n '1,220p' OpenSuperWhisper/Indicator/IndicatorWindow.swift
    sed -n '1,220p' OpenSuperWhisper/Indicator/IndicatorWindowManager.swift
    sed -n '1,220p' .docs/PLANS.md

To validate the SDK exposes the new glass APIs in this environment, typecheck a small temporary Swift file:

    xcrun swiftc -sdk /Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -target arm64-apple-macos15.0 -typecheck /tmp/liquid_glass_check.swift

Expected result: typechecking succeeds when the temp file references `GlassEffectContainer` and `.glassEffect(...)`.

After implementing the overlay update, run:

    xcodebuild build -project /Users/axel/Desktop/Code_Projects/Personal/Whisper/OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath /Users/axel/Desktop/Code_Projects/Personal/Whisper/SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet

Expected result: the app target builds successfully. Existing workspace warnings may still appear, but there should be no new compile failures from the overlay changes.

## Validation and Acceptance

Acceptance requires both build validation and manual UI inspection.

First, run the full build command above and confirm the project compiles. Then launch the app and trigger the hotkey popup in both recording and transcribing states. The overlay should appear near the lower center of the active screen as before, but it should now feel lighter and more transparent. The transcript area should remain separated from the status row without reading as a darker inset box. The popup should still expand downward as transcript text grows, and the separator should remain visible without looking like a hard line.

## Idempotence and Recovery

These changes are safe to reapply because they only affect the overlay view composition and documentation. If the native glass styling causes a visual regression on supported macOS versions, the safest recovery is to keep the helper structure and tune the tint, stroke, or shadow values rather than removing the availability-gated branch entirely. If the fallback diverges from the native look, adjust both branches together and re-run the build.

## Artifacts and Notes

Build validation used:

    xcodebuild build -project /Users/axel/Desktop/Code_Projects/Personal/Whisper/OpenSuperWhisper.xcodeproj -scheme OpenSuperWhisper -destination 'platform=macOS' -clonedSourcePackagesDirPath /Users/axel/Desktop/Code_Projects/Personal/Whisper/SourcePackages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet

Observed result: build succeeded with no new overlay-related errors. Existing workspace warnings remained, including the known `ContentView.swift` Swift concurrency warning and the existing `libomp.dylib` deployment-version linker warning.

## Interfaces and Dependencies

`OpenSuperWhisper/Indicator/IndicatorWindow.swift` should expose availability-gated helper methods that style the outer popup surface and transcript surface independently. The native branch should use SwiftUI’s glass APIs on supported macOS versions:

    GlassEffectContainer(spacing: ...)
    view.glassEffect(.regular.tint(...), in: .rect(cornerRadius: ...))

The fallback branch should use SwiftUI materials and standard shapes:

    RoundedRectangle(cornerRadius: ...)
        .fill(...)
        .background { RoundedRectangle(...).fill(.ultraThinMaterial or .regularMaterial) }
        .overlay { RoundedRectangle(...).strokeBorder(...) }

Revision note: created during implementation so the overlay visual redesign is documented in-repo with the same living-plan structure used elsewhere in this workspace.

Revision note: updated after the follow-up styling pass to record the stronger shared glass treatment for the status row and transcript background, plus the repeated full-build validation.

Revision note: updated after the layout review pass to record the simplification from multiple bordered sub-surfaces to one clearer HUD hierarchy.
