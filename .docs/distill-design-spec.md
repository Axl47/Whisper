# Distill — Media Compression for the Smart Lattice

*Controlled transformation. Choose outcomes, not settings.*

---

## Overview

Distill is a local-first media compression tool that inverts the traditional compression workflow. Instead of requiring users to understand bitrate, CRF values, and codec settings, Distill takes a constraint — a platform target or a file size — and surfaces a ranked set of concrete output options showing what the result will actually look like. The user chooses an outcome, not a configuration.

The app runs entirely on-device. Media never leaves the phone. FFmpeg-kit handles encoding, and a pure-function optimizer core generates the option set from source metadata and target constraints. The optimizer is platform-agnostic logic that also powers the Forge CLI `distill` block and the web Forge builder node.

### Lattice Position

Distill lives in the **Synapse System** cluster alongside Conduit, Herald, Echo, and Vigil — infrastructure-layer tools that move, transform, and bridge data. Its compression engine is a natural Forge block (typed transformation with clear input/output contracts), and its platform-preset knowledge base is an agent-readable structured resource.

### Core Metaphor

Distillation — reducing a substance to its essential components under controlled conditions. The name, the copper accent palette, and the overall restraint of the UI all reference this. The app feels like a precision instrument, not a utility with sliders.

---

## Design Principles (Distill-Specific)

**Outcomes over settings.** The primary interface shows what you'll get (resolution, fps, estimated size, preview frame), not what you need to configure. Manual mode exists as an escape hatch, never the default path.

**Show, don't describe.** Each option card includes a real single-frame encode preview at target settings. The user sees actual compression artifact levels — blocking, banding, detail loss — before committing. Quality is visual, not numeric.

**One video, one target, one tap.** The core flow is three decisions: which video, which target, which option. Everything else is progressive disclosure.

**Platform-aware by default.** The app ships with current sharing limits for major platforms. These are maintained as a structured JSON resource that can be updated independently of app releases and queried by agents.

---

## Architecture

### Optimizer Core

The optimizer is a pure function with no FFmpeg dependency:

```
analyze(source: MediaMeta, constraint: Constraint) → OptionSet
```

**MediaMeta** (produced by ffprobe / FFmpeg-kit's media information API):
- `width`: number (pixels)
- `height`: number (pixels)
- `fps`: number (source frame rate)
- `duration`: number (seconds)
- `codec`: string (e.g. "h264", "hevc")
- `bitrate`: number (kbps, total)
- `audioBitrate`: number (kbps, audio track; default 128 if undetectable)
- `fileSize`: number (bytes)
- `hasAudio`: boolean

**Constraint** (one of):
- `PlatformTarget`: `{ platform: PlatformId, limit: number (bytes) }`
- `SizeTarget`: `{ maxSize: number (bytes) }`
- `ManualTarget`: `{ width, height, fps, crf?, bitrate? }`

**OptionSet**:
- `source`: MediaMeta
- `constraint`: Constraint
- `options`: Option[] (sorted by quality score descending, max 6)
- `noCompressionNeeded`: boolean (true if source already fits constraint)

**Option**:
- `id`: string (e.g. "720p-30")
- `width`: number
- `height`: number
- `fps`: number
- `codec`: "h264" (default; "hevc" only when target platform explicitly supports it)
- `estimatedBitrate`: number (kbps, video only)
- `estimatedSize`: number (bytes)
- `crf`: number (derived from target bitrate)
- `qualityScore`: number (0–100)
- `audioPassthrough`: boolean (true unless audio must be re-encoded to fit)

#### Quality Score Calculation

The quality score is a heuristic composite that ranks options by perceptual quality relative to source:

```
availableBitrate = (targetBytes - audioBytes) * 8 / duration  // bps
neededBitrate = presetMinBitrate * (fps / 60) * 1.2
qualityBase = clamp(availableBitrate / neededBitrate, 0, 1)
resolutionBonus = (optionPixels / sourcePixels) * 0.30
fpsBonus = (optionFps / sourceFps) * 0.15
qualityScore = clamp((qualityBase * 0.55 + resolutionBonus + fpsBonus) * 100, 0, 98)
```

Minimum bitrate thresholds per resolution tier (at 30fps baseline):
| Resolution | Min Bitrate (kbps) |
|------------|-------------------|
| 1080p      | 3000              |
| 900p       | 2200              |
| 720p       | 1500              |
| 540p       | 800               |
| 480p       | 500               |
| 360p       | 300               |

Options below 40% of their tier's minimum bitrate are excluded. Options with qualityScore below 20 are excluded. The option set is capped at 6 entries after deduplication by resolution+fps pair.

#### Resolution Presets

The optimizer evaluates these resolution tiers (only tiers at or below source resolution):

| Label | Width | Height |
|-------|-------|--------|
| 1080p | 1920  | 1080   |
| 900p  | 1600  | 900    |
| 720p  | 1280  | 720    |
| 540p  | 960   | 540    |
| 480p  | 854   | 480    |
| 360p  | 640   | 360    |

FPS options evaluated: 60, 30, 24 (only values at or below source fps).

#### Codec Policy

Default codec is H.264 (universally compatible). The optimizer selects H.264 unless:
- The target platform is known to support HEVC and the user has explicitly opted into HEVC in settings.
- Manual mode with explicit codec selection.

AV1 is not offered in Phase 1 due to slow mobile encoding. Future consideration for Phase 3.

Audio is passed through (copy, no re-encode) whenever possible. Audio re-encode to AAC 128kbps only when:
- Source audio codec is incompatible with output container.
- Audio passthrough would cause the output to exceed the target size.

### Preview Engine

For each option in the set, Distill generates a single-frame encode preview:

1. Extract one keyframe from the source at the 30% timestamp (avoids black intro frames, typically lands on representative content).
2. Encode that single frame at the option's target resolution, CRF, and codec settings using FFmpeg-kit.
3. Store the resulting frame as a bitmap in memory (not written to disk).

Expected latency: 100–300ms per frame on modern Android devices (Snapdragon 8-series). All options are encoded in parallel on background threads. The UI shows option cards with placeholder shimmer until their preview frame resolves.

If preview generation fails for any option (e.g., memory pressure), the card falls back to a downscaled thumbnail of the source at target resolution (no compression artifact simulation, but still shows resolution difference).

### Platform Presets

Stored as a structured JSON file bundled with the app and updatable via a simple config fetch (no app update required):

```json
{
  "version": 3,
  "updated": "2026-03-06",
  "platforms": [
    {
      "id": "discord",
      "name": "Discord",
      "icon": "discord",
      "limits": {
        "free": { "maxSize": 26214400, "note": "25 MB" },
        "nitro": { "maxSize": 524288000, "note": "500 MB" }
      },
      "supportedCodecs": ["h264"],
      "maxDuration": null,
      "maxResolution": null
    },
    {
      "id": "whatsapp",
      "name": "WhatsApp",
      "icon": "whatsapp",
      "limits": {
        "default": { "maxSize": 16777216, "note": "16 MB" }
      },
      "supportedCodecs": ["h264"],
      "maxDuration": null,
      "maxResolution": null
    },
    {
      "id": "telegram",
      "name": "Telegram",
      "icon": "telegram",
      "limits": {
        "default": { "maxSize": 2147483648, "note": "2 GB" }
      },
      "supportedCodecs": ["h264", "hevc"],
      "maxDuration": null,
      "maxResolution": null
    },
    {
      "id": "twitter",
      "name": "Twitter / X",
      "icon": "twitter",
      "limits": {
        "default": { "maxSize": 536870912, "note": "512 MB" }
      },
      "supportedCodecs": ["h264"],
      "maxDuration": 140,
      "maxResolution": 1920
    },
    {
      "id": "instagram",
      "name": "Instagram",
      "icon": "instagram",
      "limits": {
        "reel": { "maxSize": 104857600, "note": "100 MB", "maxDuration": 90 },
        "story": { "maxSize": 104857600, "note": "100 MB", "maxDuration": 60 },
        "feed": { "maxSize": 104857600, "note": "100 MB", "maxDuration": 60 }
      },
      "supportedCodecs": ["h264"],
      "maxResolution": 1920
    },
    {
      "id": "email",
      "name": "Email",
      "icon": "email",
      "limits": {
        "default": { "maxSize": 26214400, "note": "25 MB" }
      },
      "supportedCodecs": ["h264"],
      "maxDuration": null,
      "maxResolution": null
    }
  ]
}
```

This file is also the agent-readable resource. An agent querying "what's Discord's file size limit?" reads this directly.

### Observation Store

Local SQLite database tracking usage patterns. Schema:

```sql
CREATE TABLE compressions (
  id TEXT PRIMARY KEY,
  timestamp INTEGER NOT NULL,
  source_size INTEGER NOT NULL,        -- bytes
  source_resolution TEXT NOT NULL,      -- "1920x1080"
  source_fps INTEGER NOT NULL,
  source_duration REAL NOT NULL,        -- seconds
  target_platform TEXT,                 -- platform id or null for custom
  target_size INTEGER NOT NULL,         -- bytes constraint
  selected_resolution TEXT NOT NULL,    -- "1280x720"
  selected_fps INTEGER NOT NULL,
  selected_quality_score INTEGER NOT NULL,
  selected_option_rank INTEGER NOT NULL, -- 0 = top recommendation
  output_size INTEGER NOT NULL,         -- actual bytes
  encode_duration_ms INTEGER NOT NULL,
  source_app TEXT                       -- package name that shared the file, if available
);
```

Derived signals (computed on read, not stored):
- `mostUsedPlatform`: platform id with highest count in last 30 days.
- `preferredOptionRank`: average rank of selected option (lower = user trusts recommendations; higher = user always overrides).
- `qualityPreference`: "resolution" if user consistently picks higher-res lower-fps; "framerate" if opposite; "balanced" otherwise.
- `frequentSourceApps`: top 3 source apps by count.
- `compressionFrequency`: average compressions per day over last 14 days.

These signals feed the adaptive UX (Phase 2) and are agent-readable via a structured query interface.

---

## Visual Design

### Identity

**Name**: Distill
**Tagline**: Media compression. (Shown as monospaced subtitle beneath the app title.)
**App icon concept**: A diamond/rhombus shape (◇) — the refined output of a raw material. Copper/amber on dark. Clean, geometric, no gradients on the icon itself.

### Palette

The palette references copper distillation equipment — warm metallic accent on near-black ground. Color is used semantically, never decoratively.

```
--bg-root:        #0A0A0B     (environment background, behind the phone frame)
--bg-surface:     #111113     (primary surface / card background)
--bg-raised:      rgba(255, 255, 255, 0.02)   (subtle card elevation)
--bg-hover:       rgba(255, 255, 255, 0.04)   (interactive hover state)

--accent:         #D4A574     (copper — primary action, selected states, progress)
--accent-muted:   rgba(212, 165, 116, 0.08)   (accent backgrounds)
--accent-border:  rgba(212, 165, 116, 0.30)   (accent borders on active elements)
--accent-glow:    rgba(212, 165, 116, 0.06)   (subtle selected card fills)

--text-primary:   rgba(255, 255, 255, 0.80)
--text-secondary: rgba(255, 255, 255, 0.40)
--text-tertiary:  rgba(255, 255, 255, 0.20)
--text-ghost:     rgba(255, 255, 255, 0.12)

--border:         rgba(255, 255, 255, 0.06)
--border-hover:   rgba(255, 255, 255, 0.10)

--quality-high:   #4ADE80     (quality score ≥ 75)
--quality-mid:    #D4A574     (quality score 50–74)
--quality-low:    #F59E0B     (quality score 30–49)
--quality-poor:   #EF4444     (quality score < 30)

--success:        #4ADE80     (completion checkmark, reduction percentage)
```

No gradients in the UI except: the progress bar fill (subtle `--accent` to a lighter copper) and the simulated preview frames (scene rendering only).

### Typography

Three-font system. No system fonts, no Inter, no Roboto.

| Role | Font | Weight | Usage |
|------|------|--------|-------|
| Display | Playfair Display | 500 | App title ("Distill"), reduction stat on completion screen. Serif warmth contrasts the technical UI. |
| Body | DM Sans | 300–600 | Labels, descriptions, button text, import zone text. |
| Data | DM Mono | 300–500 | All numeric values, metadata, filenames, section labels, version tag, quality scores, size values, bitrate, fps, resolution labels, timestamps. |

Section labels: DM Mono, 9px, `--text-tertiary`, uppercase, letter-spacing 1.5px. This pattern is consistent throughout the app for all section dividers ("Target", "Options", "Recent", "Resolution", "Frame Rate", etc.).

### Spacing & Layout

The app targets a 380dp-wide mobile viewport. All values below are in dp (density-independent pixels).

```
Screen horizontal padding:     20
Card internal padding:         14
Card border-radius:            12
Card border:                   1px solid var(--border)

Section label margin-top:      20
Section label margin-bottom:   10

Option card padding:           10
Option card border-radius:     10
Option card gap (grid):        12
Option card margin-bottom:     8

Platform chip padding:         10 horizontal, 12 vertical
Platform chip border-radius:   10
Platform chip min-width:       68
Platform chip gap:             8

Button padding:                14 vertical
Button border-radius:          12
Button margin-top:             16

Preview thumbnail (card):      120 × 68
Preview thumbnail (full):      280 × 158
Source thumbnail (source card): 72 × 42

Quality ring size (card):      30
Quality ring size (overlay):   36
Quality ring stroke-width:     2.5

Progress bar height:           3
Size bar height:               3
```

### Motion

All animations are CSS-only. No spring physics, no JS animation libraries. The aesthetic is precise and mechanical, matching the instrument feel.

| Animation | Duration | Easing | Trigger |
|-----------|----------|--------|---------|
| Screen enter (fadeUp) | 300–400ms | ease | Screen transition |
| Card stagger | 200ms + (index × 60ms) | ease | Option list population |
| Size bar fill | 500ms | ease | Option selection / target change |
| Quality ring stroke | 600ms | ease | Option render |
| Progress bar | continuous, linear | linear | Compression encode |
| Completion checkmark (scaleIn) | 400ms | custom (overshoot at 60%) | Encode complete |
| Hover state transitions | 250ms | ease | All interactive elements |
| Preview overlay enter | 250ms | ease | Double-tap option card |

The `fadeUp` keyframe:
```css
@keyframes fadeUp {
  from { opacity: 0; transform: translateY(12px); }
  to   { opacity: 1; transform: translateY(0); }
}
```

The `scaleIn` keyframe (completion checkmark):
```css
@keyframes scaleIn {
  0%   { transform: scale(0.5); opacity: 0; }
  60%  { transform: scale(1.05); }
  100% { transform: scale(1); opacity: 1; }
}
```

No micro-interaction animations on tap (this is a utility, not a toy). Hover and selection states are simple property transitions.

---

## Screens

### 1. Import Screen

The entry point. Shown when the app is opened directly (not via share sheet).

**Layout:**
- Top: App title "Distill" (Playfair Display, 22px, `--text-primary` biased warm: `#E8E0D4`) with version tag (DM Mono, 9px, `--text-ghost`) right-aligned on the same baseline.
- Below title: "Media Compression" subtitle (DM Mono, 10px, `--text-tertiary`, uppercase, letter-spacing 1.5px).
- Import zone: Centered card, dashed border (1px dashed `rgba(255,255,255,0.08)`), border-radius 16px, padding 48px vertical / 24px horizontal. Contains:
  - Diamond icon (◇), 32px, opacity 0.4.
  - "Drop a video or tap to select" (DM Sans, 14px, `--text-secondary`).
  - "MP4 · MOV · WEBM · MKV" (DM Mono, 10px, `--text-ghost`).
- Import zone hover: border-color shifts to `rgba(212,165,116,0.25)`, background to `rgba(212,165,116,0.02)`.
- Below import zone (28dp gap): "Recent" section.
  - Section label.
  - List of up to 5 recent files, each row:
    - Thumbnail (40 × 28dp, border-radius 4, tinted background from file metadata).
    - Filename (DM Mono, 11px, `--text-secondary`).
    - Size + duration (DM Mono, 9px, `--text-ghost`).
    - Separated by 1px borders (`rgba(255,255,255,0.03)`), last item no border.
    - Tapping any row loads that file into the analyze screen.

**Share sheet entry**: When opened via Android share intent, the import screen is skipped entirely. The shared file loads directly into the analyze screen.

### 2. Analyze Screen

The core screen. Three zones stacked vertically.

#### 2a. Source Card

Positioned at the top after a back button ("← back", DM Mono, 11px, `--text-tertiary`).

Card layout:
- Top row: Source thumbnail (72 × 42dp, border-radius 6, showing a full-quality preview frame) alongside filename (DM Mono, 11px, `--text-secondary`, truncated with ellipsis) and file size (DM Mono, 16px, `--text-primary`, font-weight 500).
- Below: 2×2 metadata grid:
  - Resolution: e.g. "1920×1080"
  - Frame Rate: e.g. "60 fps"
  - Duration: e.g. "2:34"
  - Codec: e.g. "H.264"
  - Each cell: label (section label style) + value (DM Mono, 13px, `--text-secondary` strong: `rgba(255,255,255,0.7)`).

#### 2b. Target Selector

Section label: "Target"

Horizontal scrolling row of platform chips. Each chip:
- Icon (18px emoji or platform glyph).
- Platform name (DM Sans, 10px, `--text-secondary`).
- Size limit (DM Mono, 9px, `--text-tertiary`). Shown as "25 MB", "16 MB", "2 GB", etc.
- Active state: border `--accent-border`, background `--accent-glow`.

The chip order reflects usage frequency after Phase 2 observation kicks in. Default order (Phase 1): Discord, WhatsApp, Telegram, Twitter, Instagram, Email, Custom.

**Custom target**: Selecting the "Custom" chip reveals a slider + numeric display below the chip row:
- Container: padding 12/14, background `--bg-raised`, border 1px `--border-hover`, border-radius 10.
- Slider: range 5–500 MB, 3px track, copper thumb (14px circle with 2px `#1a1a1c` border).
- Numeric readout: DM Mono, 14px, `--accent`, right-aligned, min-width 52dp.

**Platform sub-targets**: For platforms with multiple limits (Instagram reel vs story vs feed, Discord free vs Nitro), tapping the active chip a second time reveals a secondary selector beneath the chip row showing the available tiers. Default is the most common tier (Discord free, Instagram reel).

#### 2c. Option Cards

Section label: "Options" with a right-aligned "manual" toggle (DM Mono, 10px, `--text-tertiary`, ○/◉ prefix).

Each option card is a two-column grid:
- Left column: Preview frame (120 × 68dp) — the actual single-frame encode at target settings.
- Right column (flex vertical, space-between):
  - Top: Resolution label (DM Mono, 13px, `--text-primary`, weight 500) + fps (DM Mono, 10px, `--text-tertiary`).
  - Top-right: Quality ring + optional "Best" badge (DM Mono, 8px, `--accent`, 1px `--accent-border` rounded box).
  - Bottom: Size bar (visual + numeric) + bitrate label (DM Mono, 9px, `--text-ghost`).

**Quality Ring**: SVG circle, 30dp diameter, 2.5px stroke. Background ring `rgba(255,255,255,0.06)`. Foreground stroke colored by quality tier (see palette). Centered number in DM Mono at 30% of ring diameter. Ring is rotated -90deg so fill starts at top.

**Size Bar**: 3px height, full width of the right column. Background `rgba(255,255,255,0.06)`. Fill colored `rgba(255,255,255,0.25)` normally, `--accent` when >90% of target (tight fit warning). Numeric readout right of bar: DM Mono, 10px, matching fill color.

**Selection**: Tapping a card selects it (active border/background treatment). The compress button updates to show the selected option's estimated size.

**Preview overlay**: Double-tapping a card opens a full-screen overlay (dark scrim `rgba(0,0,0,0.85)`) with:
- Close button (top-right, DM Mono, 11px).
- Large preview frame (280 × 158dp).
- Resolution + fps label.
- Quality ring (36dp) + size/bitrate text.
- "Single-frame encode preview · actual output quality" footnote (DM Mono, 9px, `--text-ghost`).

**"No compression needed" state**: If the source already fits the target, the option area shows centered text: "Target is larger than source — no compression needed." (DM Mono, 12px, `--text-tertiary`).

**Compress button**: Full-width, border-radius 12, border `--accent-border`, background `--accent-muted`, text `--accent`, DM Sans 14px weight 500. Label: "Distill → {size} MB". Disabled (opacity 0.3) when no option is selected. Triggers the encode and transitions to the compressing screen.

#### 2d. Manual Mode

Toggling manual mode replaces the option cards with a parameter panel:

Card with `--bg-raised` background, border, border-radius 12, padding 16.

Four parameter rows, each with:
- Left: label (section label style, 10px).
- Right: value (DM Mono, 13px, `--text-secondary`) + hint (DM Mono, 9px, `--text-ghost`).

| Parameter | Default | Hint | Control |
|-----------|---------|------|---------|
| Resolution | 1280×720 | 720p | Dropdown / cycle |
| Frame Rate | 30 | fps | Dropdown / cycle |
| CRF | 23 | lower = better | Slider (18–36) |
| Codec | H.264 | universal | Toggle H.264 / HEVC |

The compress button in manual mode shows an estimated size calculated from the manual parameters. If the estimate exceeds the selected platform target, the button label shows a warning: "Distill → ~{size} MB (exceeds target)".

### 3. Compressing Screen

Centered layout, entered via fade-up transition.

- Title: "Distilling…" (Playfair Display, 18px, `#E8E0D4`).
- Preview frame of the selected option (200 × 113dp, centered, border-radius 8, 1px `--border`).
- Config summary: "{resShort} · {fps}fps · H.264" (DM Mono, 12px, `--text-tertiary`).
- Progress percentage: DM Mono, 28px, `--accent`, weight 500. Updates in real-time from FFmpeg-kit frame callback.
- Progress bar: 240dp max-width, centered, 3px height, copper gradient fill. Linear transition matching actual encode progress.
- ETA: DM Mono, 10px, `--text-ghost`. Calculated from (elapsed_time / progress_fraction) - elapsed_time. Shows "Finalizing…" in the last 2%.
- No cancel button in Phase 1. Phase 2 adds a subtle "✕ cancel" below the ETA.

**Background encoding**: If the user navigates away from the app, encoding continues as a foreground service with a persistent notification showing progress. Completion triggers a notification with "Share" and "Save" actions.

### 4. Completion Screen

Entered via fade-up after encode finishes.

- Checkmark: 64dp circle, 2px border `rgba(74,222,128,0.4)`, centered "✓" in `--success` at 28px. Enters with `scaleIn` animation.
- "Reduction" label: section label style, centered.
- Reduction percentage: Playfair Display, 42px, `--success`. Calculated as `round((1 - outputSize / sourceSize) * 100)`. This is the hero stat.
- Size comparison: DM Mono, 12px, `--text-tertiary`. "{sourceSize} MB → {outputSize} MB".
- Output metadata grid: 2×2, same style as source card metadata. Shows Resolution, Frame Rate, Bitrate, Codec of the output.
- Action buttons (stacked):
  1. **Share to {Platform}** — copper accent style (same as compress button). Opens Android share sheet pre-targeted to the selected platform's package. Only shown if a platform (not Custom) was selected.
  2. **Save to Device** — neutral style (`--bg-raised` background, `--text-secondary` text). Saves to device gallery / Downloads.
  3. **Distill Another** — neutral style. Returns to import screen, resets all state.
- Navigation pill: 36 × 4dp, `rgba(255,255,255,0.1)`, border-radius 2, centered, 12dp margin-top. Visual affordance for home gesture.

---

## Android-Specific Implementation

### Share Sheet Integration

**Incoming (receive files)**: Register intent filters for `video/*` MIME types on the main activity. When triggered, skip the import screen and load directly into the analyze screen with the shared file. The source card shows the file as received.

**Outgoing (share results)**: After compression, the share button creates a `FileProvider` URI for the output file and launches `ACTION_SEND` with the appropriate MIME type. If a platform was selected, the intent targets that platform's package name (best-effort; falls back to generic chooser if the package isn't installed).

Platform package mapping:
| Platform | Package |
|----------|---------|
| Discord | com.discord |
| WhatsApp | com.whatsapp |
| Telegram | org.telegram.messenger |
| Twitter | com.twitter.android |
| Instagram | com.instagram.android |

### Quick Settings Tile (Phase 2)

After observing the user's most-used platform target (minimum 5 compressions to same platform in 14 days), offer a Quick Settings tile: "Distill for {Platform}". Tapping the tile opens a file picker; the selected file goes directly to the analyze screen with the platform pre-selected.

### App Shortcuts (Phase 2)

Dynamic shortcuts (long-press app icon) for the top 2 most-used platforms. Same flow as Quick Settings tile.

### Foreground Service

Encoding runs as an Android foreground service with:
- Persistent notification: "Distilling — {progress}%" with a progress bar.
- Completion notification: "Distilled to {size} MB" with Share and Save actions.
- The service survives the activity being backgrounded or destroyed.

### FFmpeg-Kit Integration

Use `ffmpeg-kit-full` package for maximum codec support. Key operations:

**Probe** (source analysis):
```kotlin
FFprobeKit.getMediaInformation(inputPath) { session ->
    val info = session.mediaInformation
    // Extract: width, height, fps, duration, codec, bitrate, audio info
}
```

**Preview frame extraction** (keyframe at 30% timestamp):
```
-ss {timestamp} -i {input} -vframes 1 -q:v 2 {output.jpg}
```

**Preview frame encode** (compress single frame at target settings):
```
-ss {timestamp} -i {input} -vframes 1 -vf scale={w}:{h} -c:v libx264 -crf {crf} {output.jpg}
```

**Full encode** (with progress callback):
```
-i {input} -vf scale={w}:{h} -r {fps} -c:v libx264 -crf {crf} -preset medium
-c:a copy  // or: -c:a aac -b:a 128k  (if audio passthrough not possible)
-movflags +faststart {output.mp4}
```

The `-movflags +faststart` flag is critical — it moves the moov atom to the start of the file so the output is streamable, which matters for platform uploads.

Progress tracking: FFmpeg-kit provides `statisticsCallback` with frame number, fps, bitrate, time, and size. Calculate progress as `currentTime / totalDuration`.

### Storage

- Compressed outputs saved to app-specific cache directory during encoding.
- On "Save to Device": copied to MediaStore (scoped storage compliant) under `Movies/Distill/`.
- On "Share": served from cache via FileProvider.
- Cache cleanup: outputs older than 24 hours are deleted on app launch.
- Observation database: `distill.db` in app-specific internal storage.

---

## Phased Implementation

### Phase 1 — Core (MVP)

Deliverables:
1. FFmpeg-kit integration: probe, single-frame preview encode, full encode with progress.
2. Optimizer function: option generation from source metadata + constraint.
3. Platform presets: bundled JSON, all 6 platforms with current limits.
4. Import screen: file picker, recent files list.
5. Analyze screen: source card, platform selector, option cards with real preview frames, quality ring, size bar.
6. Manual mode: direct parameter control.
7. Compressing screen: progress with ETA.
8. Completion screen: reduction stat, share, save.
9. Share sheet integration: incoming (receive) and outgoing (send to platform).
10. Foreground service for background encoding.
11. Preview overlay on double-tap.

Out of scope for Phase 1: observation store, adaptive ordering, Quick Settings tile, app shortcuts, batch compression, cancel mid-encode, audio-only mode, Forge integration.

### Phase 2 — Observation + Polish

Deliverables:
1. Observation SQLite store: log every compression with metadata.
2. Derived signals: compute most-used platform, quality preference, option rank preference.
3. Adaptive platform ordering: re-sort chip row by frequency.
4. Adaptive option recommendation: "Best" badge placement influenced by user's historical selections.
5. Quick Settings tile for most-used platform.
6. App shortcuts for top 2 platforms.
7. Batch compression: multi-select in picker, same target applied to all, sequential encode with aggregate progress.
8. Cancel mid-encode.
9. Audio extraction mode: strip video, output audio-only (MP3/AAC).
10. Background notification actions: Share and Save from notification.
11. One-tap shortcut suggestions: after detecting repeated identical workflows, suggest creating a home screen shortcut.

### Phase 3 — Ecosystem

Deliverables:
1. Forge `distill` block (CLI + web). See the Forge integration appendix.
2. Analyze-only mode exposed to agents.
3. Conduit bridge: if Conduit is running on both devices, compress on phone and send result directly to desktop (or receive a desktop file on phone for compression).
4. HEVC opt-in for supported platforms.
5. Platform preset auto-update: periodic fetch of latest limits from a hosted JSON endpoint (no app update needed).
6. Image compression mode: extend the same target-fit paradigm to images (JPEG/WebP quality, resolution reduction, format conversion). Same optimizer pattern, different encoder.

---

## Agent Interface

### Query Patterns

An agent with access to the Distill observation store (via Nexus tool API in Phase 3) can:

- Read compression history: "How many videos did the user compress this week? What platforms?"
- Read derived signals: "What's the user's most-used platform? Do they prefer resolution or framerate?"
- Read platform presets: "What's WhatsApp's size limit?"
- Invoke compression (via Forge CLI): `forge express "distill(target=discord)" --input video.mp4`
- Plan compression (via Forge CLI): `forge express "distill(target=25MB, analyze=true)" --input video.mp4 --json-output`

### Structured Output (Analyze Mode)

When invoked with `analyze=true`, the distill block returns the full option set as JSON:

```json
{
  "success": true,
  "result": {
    "type": "distill-analysis",
    "source": {
      "width": 1920,
      "height": 1080,
      "fps": 60,
      "duration": 154.2,
      "codec": "h264",
      "bitrate": 12400,
      "fileSize": 250298368,
      "hasAudio": true
    },
    "constraint": {
      "type": "platform",
      "platform": "discord",
      "maxSize": 26214400
    },
    "noCompressionNeeded": false,
    "options": [
      {
        "id": "720p-30",
        "width": 1280,
        "height": 720,
        "fps": 30,
        "codec": "h264",
        "estimatedBitrate": 1200,
        "estimatedSize": 24800000,
        "crf": 26,
        "qualityScore": 72,
        "audioPassthrough": true
      }
    ]
  },
  "timing": { "total_ms": 45 },
  "warnings": []
}
```

An agent can inspect this, select an option, and invoke the actual encode with explicit parameters — or present the options to the user for decision.
