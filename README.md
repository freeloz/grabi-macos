# Grabi

**Record your screen, no drama.** Grabi is a native macOS screen recorder
with one window that holds everything — record, your recordings, settings.
Open it, hit the red dot, done. The opposite of OBS. It also keeps a menu
bar item for recording without opening the window.

- **4 independent sources**, any combination: screen (full display, a
  window, or a region), selfie camera, microphone, and system audio.
- **Picture-in-picture camera** with free shape (circle / square /
  rectangle), position and size — adjustable **live** while recording, by
  dragging the floating box you always see while you record. Mirrored,
  like every selfie.
- **Live preview**: what you see is exactly what gets recorded.
- **Pause/resume** with no gaps in the file. Floating pill with a timer,
  excluded from the recording (like every Grabi window).
- **A single .mov** with hardware HEVC video and the microphone and system
  audio on **two separate tracks** (~2.2 GB/hour observed at 1080p).
- Visual display and window picker with thumbnails, red border around the
  recorded area, notification with thumbnail when you finish, onboarding
  with Grabi (the mascot), global shortcuts ⌘⇧2 and ⌘⇧P.
- In 5 languages (English default), with the brand voice. Everything local:
  nothing leaves your Mac.

## Download

Latest version for macOS 13+ (signed DMG):

- **https://dl.grabi.net/macos/latest/Grabi.dmg**
- Manifest with version and checksum: https://dl.grabi.net/macos/latest.json
- Previous versions: `https://dl.grabi.net/macos/v<version>/…` and the
  [GitHub releases](https://github.com/freeloz/grabi-macos/releases).

Every DMG publishes its SHA-256 next to the file (`.sha256` and
`SHA256SUMS.txt`). Verify it like this:

```bash
shasum -a 256 Grabi-*.dmg   # must match the published .sha256
```

> Interim signing: local "Grabi Dev" certificate with hardened runtime (no
> Apple notarization yet). First launch: System Settings → Privacy &
> Security → "Open Anyway". If macOS claims the app "is damaged" (recent
> versions do this to non-notarized apps), run
> `xattr -cr /Applications/Grabi.app` once — it only clears the download
> mark. The official site is [grabi.net](https://grabi.net).

## Updates

From 0.1.4 on, Grabi updates itself with [Sparkle](https://sparkle-project.org):
a quiet daily check against the EdDSA-signed feed at
`https://dl.grabi.net/macos/appcast.xml`, plus a manual "Check for updates…"
in Settings. Release architecture (one-command publishing, feed layout, key
custody): [docs/RELEASING.md](docs/RELEASING.md). Homebrew packaging is
prepared in [packaging/homebrew/](packaging/homebrew/) (publishes after
notarization).

## Reporting problems

Settings → "Report a problem…" opens a pre-filled GitHub issue with your app
version, macOS version, chip and language (nothing else). Updater events are
logged to `~/Library/Logs/Grabi/updater.log` — short lines, no personal data —
attach it if your report is about updates. Or just open an
[issue](https://github.com/freeloz/grabi-macos/issues/new/choose) — any
language is welcome.

## Build and run

Requirements: macOS 13+, Swift 5.9+ (the Command Line Tools are enough), no
external dependencies — Apple frameworks only.

```bash
./make-app.sh          # builds (release) and packages dist/Grabi.app
open dist/Grabi.app
```

`make-app.sh` signs with the local **"Grabi Dev"** identity if it exists in
your keychain (create it once: Keychain Access → Certificate Assistant →
Create a Certificate → type *Code Signing*, name `Grabi Dev`). With a
stable signature, the screen/camera/mic permissions survive rebuilds; with
an ad-hoc signature, macOS re-asks for the screen permission on every
build.

Engine verification (no permissions needed, runs on any machine):

```bash
swift run EngineChecks
```

Endurance test (stable memory during long recordings):

```bash
./scripts/monitor-memory.sh   # while you record 30-60 min
```

## Architecture

Swift Package with three targets:

```
Sources/
├── RecordEngine/    The engine. Zero UI.
│   ├── RecordEngine.swift       Facade: preflight → preview → start/pause/stop
│   ├── CapturePipeline.swift    Capture shared between preview and recording
│   ├── ScreenCapturer.swift     ScreenCaptureKit: screen/window/region + system audio
│   ├── CameraCapturer.swift     AVFoundation: camera
│   ├── MicrophoneCapturer.swift AVFoundation: microphone (native channels)
│   ├── PiPCompositor.swift      Core Image + Metal: PiP with shapes, on the GPU
│   ├── MovieWriter.swift        Streaming AVAssetWriter; pause via PTS offset
│   └── Preflight.swift          Availability and permissions per source
├── RecordUI/        The Grabi design system (design/) as SwiftUI.
│   ├── Tokens.swift             Light/dark colors, spacing, radii, motion
│   ├── Mascot.swift             The mascot and the traffic light (8 poses)
│   └── …                        Buttons, source rows, segmented, toasts, gallery
├── RecordApp/       The app: main window (record · library · settings),
│                   menu bar quick access, overlays and the pill
└── EngineChecks/    Engine integration verification
```

Key engine decisions:

- **One pipeline, two consumers**: the preview and the writer share
  capturers and compositor; starting a recording just "hooks up" the
  writer.
- **Synchronization**: every source stamps PTS with the host clock; the
  writer starts its session on the first video frame and AVAssetWriter
  aligns the rest. Pausing accumulates an offset (measured with the same
  clock) that is subtracted from each PTS: N pauses, zero gaps.
- **Thread-safety**: buffers arrive on different queues; all appends are
  serialized on the writer's internal queue.
- **Streaming to disk**: frames are never accumulated in RAM; frames that
  arrive while the encoder is busy are dropped (real time).

`design/` contains the brand manual, the design system, and the approved
prototype (Phases 0–4): it is the UI specification. The internal gallery
(Settings → System gallery) shows every component in all of its states to
verify fidelity.

## Settings

- **Recording quality** (v0.1.1): *Standard* (up to 1080p, ~3 GB/hour,
  default) or *Sharp* (native source resolution up to 4K; the bitrate
  scales proportionally with the pixel area to keep per-pixel quality,
  capped at 32 Mbps). Aspect ratio is always preserved.
- **Recordings folder** and **global shortcuts** (⌘⇧2 · ⌘⇧P).
- **Quick access in the menu bar**: on by default; turn it off to keep Grabi
  in its window only.

## Languages

Grabi speaks **English** (the default language), **Spanish**,
**Portuguese**, **French**, and **German**, automatically following the
system language (no language picker of its own). The permission messages
use the real System Settings paths in each language. The folder
(`~/Movies/Grabi`) and the file names (`Grabi 2026-08-20 18.30.45.mov`)
are deliberately neutral: they don't change if you switch languages.

**Contributing a translation**: each target keeps its catalogs in
`Sources/<Target>/Resources/<language>.lproj/Localizable.strings` (plus
`Support/InfoPlist/` for the permission dialogs). Copy the `en.lproj`
folder to your language code, translate with the brand voice (warm,
simple, honest — see `design/`), keep the `%@`/`%d` placeholders, and
verify the result with the screenshot tool:
`.build/debug/RecordApp --screenshots /tmp/i18n -AppleLanguages "(xx)"`.

## Permissions

Grabi needs Screen Recording (includes system audio), Camera, and
Microphone — only to record; the app explains it and takes you to the
exact System Settings pane. If a source is unavailable or missing a
permission, Grabi warns you **before** starting and offers to record
without it.

## Known limitations (v0.1)

- Distribution: without an Apple Developer account there is no
  notarization; the app only runs on machines where it is built/signed
  locally.
- Window capture follows the window, but the indicator border and the
  selfie-box mapping use the position it had when recording started.
- Device picker (another camera/mic) and quality settings: deliberately
  out of scope for v0.1.
