# Architecture

Grabi is a small app, and the architecture is here to keep it that way: one
place to change each kind of thing, and the rules that matter covered by
tests that run in milliseconds.

## The layers

```
GrabiDomain      entities, value objects, ports        no frameworks at all
      ↑
GrabiUseCases    what the app does, as use cases       depends only on the domain
      ↑
RecordApp        SwiftUI screens + adapters            wires ports to reality
RecordEngine     ScreenCaptureKit / AVFoundation       capture and writing
RecordUI         the design system as components       tokens, mascot, controls
```

Dependencies point inward, always. The domain does not know that
ScreenCaptureKit, SwiftUI or UserDefaults exist; that is what makes it
testable without a Mac window, a camera or a permission dialog.

### GrabiDomain

Entities and value objects — `SourceSelection`, `CaptureTarget`,
`CameraLayout`, `RecordingQuality`, `DeviceSelection`, `PermissionReport`,
`RecordingPlan`, `Recording`, `RecordingState`, `AppLanguage` — plus the
**ports**: one protocol per thing the app needs from the outside world
(`CaptureEnginePort`, `MicrophoneMonitorPort`, `PermissionsPort`,
`DeviceDirectoryPort`, `RecordingLibraryPort`, `PreferencesPort`,
`LocalizationPort`, `NotifierPort`, `ClockPort`).

Rule: nothing in here imports AVFoundation, AppKit or SwiftUI. CoreGraphics
value types (`CGRect`, `CGPoint`) are allowed — they are plain geometry.

### GrabiUseCases

The behavior worth protecting, each one a small type with a single job:

| Use case | What it decides |
|---|---|
| `SyncCaptureUseCase` | who may hold the camera, screen and microphone right now |
| `StartRecordingUseCase` | permissions first, then a full-quality plan into the destination folder |
| `StopRecordingUseCase` | stop, **release the capture**, notify |
| `TogglePauseUseCase` | pause/resume without gaps |
| `RefreshDevicesUseCase` | list devices; a device that was unplugged falls back to the system default |
| `ChangeLanguageUseCase` | remember and apply the language |
| `ListRecordingsUseCase` / `DeleteRecordingUseCase` | the library, newest first; delete means the Trash |
| `EvaluateRecordability` | can this selection record, and what is blocking it |

`SyncCaptureUseCase.intent(for:)` is a pure function: given who is looking
and what is permitted, it returns whether the preview and the microphone
monitor should be running. Every camera-light bug we have had is a test in
`CaptureLifecycleTests`.

### Adapters (RecordApp/Adapters)

One file per port implementation, reusing the code that already worked:

- `RecordingEngineAdapter` → the ScreenCaptureKit/AVFoundation engine
- `MicrophoneMonitorAdapter` → the level-meter session
- `TCCPermissions` → preflight + the exact System Settings pane per source
- `AVDeviceDirectory` → cameras and microphones
- `FileSystemLibrary` → the recordings folder, Finder, pasteboard, Trash
- `UserDefaultsPreferences` → preferences
- `RuntimeLocalization` → in-app language switching
- `SystemNotifier` → the finished-recording notification

`AppEnvironment` is the composition root: the single place that knows which
adapter satisfies which port and builds the use cases from them.

### Presentation

`GrabiAppModel` coordinates the screens and holds the observable state the
SwiftUI views bind to. It no longer decides policy — it builds a
`CaptureDemand`, hands it to the use case and reflects the result. Windows
(main window, panel, pill, pickers, overlays) are controllers around
`NSWindow`; the design system lives in `RecordUI`.

## Testing

```bash
swift test            # domain + use cases, in-memory fakes, ~20 ms
swift run EngineChecks # engine integration checks (synthetic sources, no TCC)
```

`Tests/GrabiUseCasesTests/Fakes.swift` has one fake per port, each recording
what it was asked to do, so tests assert on behavior rather than on
implementation details.

Runtime checks that need a real app bundle (they exercise devices and
windows) ship as debug flags:

```bash
Grabi.app/Contents/MacOS/Grabi --lifecycletest   # capture stops when nobody is looking
Grabi.app/Contents/MacOS/Grabi --selftest        # record → stop → file on disk
Grabi.app/Contents/MacOS/Grabi --window-shot DIR # renders the real window to PNG
Grabi.app/Contents/MacOS/Grabi --screenshots DIR # every surface, for i18n review
```

## Adding something

- **A new capture source**: add it to `RecordingSource`, teach
  `SourceSelection` and `RecordingPlan` about it, extend the engine adapter.
  The use cases and the tests tell you what you missed.
- **A new screen**: a view in `RecordApp` plus, if it needs behavior, a use
  case. Views never talk to AVFoundation.
- **A new platform or a different capture backend**: implement
  `CaptureEnginePort` and change one line in `AppEnvironment`.
