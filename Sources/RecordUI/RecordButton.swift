import SwiftUI

/// The record button ★ (Phase 2 §03). It follows the traffic light and,
/// when recording, TRANSFORMS into the timer: same place, same shape,
/// different job. Full radius; height 56 by default (52 inside the panel,
/// Phase 3 §01).
public enum RecordButtonState: Equatable {
    case ready
    case recording
    case paused
}

public struct RecordButton: View {
    let state: RecordButtonState
    let elapsed: String
    let shortcutLabel: String?
    let height: CGFloat
    let onRecord: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    public init(state: RecordButtonState,
                elapsed: String = "00:00",
                shortcutLabel: String? = "⌘⇧2",
                height: CGFloat = 56,
                onRecord: @escaping () -> Void = {},
                onPause: @escaping () -> Void = {},
                onResume: @escaping () -> Void = {},
                onStop: @escaping () -> Void = {}) {
        self.state = state
        self.elapsed = elapsed
        self.shortcutLabel = shortcutLabel
        self.height = height
        self.onRecord = onRecord
        self.onPause = onPause
        self.onResume = onResume
        self.onStop = onStop
    }

    public var body: some View {
        Group {
            switch state {
            case .ready: listoBody
            case .recording: recordingBody
            case .paused: pausedBody
            }
        }
        .frame(height: height)
        .animation(GrabiAnimation.standard(), value: state)
    }

    // ready · green dot + Record + shortcut. Hover: elev.1 → elev.2.
    private var listoBody: some View {
        Button(action: onRecord) {
            HStack(spacing: GrabiSpace.s3) {
                SemaforoDot(isEnabled ? .ready : .apagado, size: 14)
                Text(L("ui.record"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GrabiColor.text)
                if let shortcutLabel {
                    Text(shortcutLabel)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(GrabiColor.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(GrabiColor.chip)
                        .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.xs))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(hovering && isEnabled ? GrabiColor.bg : GrabiColor.surface)
            .overlay(
                Capsule().strokeBorder(
                    isEnabled ? (hovering ? GrabiColor.switchOff /* #C4B89F, spec hover */ : GrabiColor.borderStrong)
                              : GrabiColor.border,
                    lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .grabiShadow(hovering && isEnabled ? .e2 : .e1)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
        .grabiFocusRing(Capsule())
        .accessibilityLabel(L("ui.record"))
        .keyboardShortcut(.defaultAction)
    }

    // recording · dark pill with timer + pause + stop.
    private var recordingBody: some View {
        HStack(spacing: GrabiSpace.s3 + 2) {
            SemaforoDot(.recording, size: 13)
            Text(elapsed)
                .font(GrabiFont.timer())
                .foregroundStyle(GrabiColor.ivoryFixed)
            Rectangle()
                .fill(GrabiColor.inkFixedSoft)
                .frame(width: 1, height: 24)
            PillCircleButton(kind: .pause, action: onPause)
            PillCircleButton(kind: .stop, action: onStop)
        }
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(GrabiColor.inkFixed)
        .clipShape(Capsule())
        .grabiShadow(.e2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: L("ui.a11y.recording"), elapsed))
    }

    // paused · amber + dimmed timer + Resume.
    private var pausedBody: some View {
        Button(action: onResume) {
            HStack(spacing: GrabiSpace.s3 + 2) {
                SemaforoDot(.paused, size: 13)
                Text(elapsed)
                    .font(GrabiFont.timer())
                    .foregroundStyle(GrabiColor.textSecondary)
                Text(L("ui.resume"))
                    .font(GrabiFont.bodySemibold)
                    .foregroundStyle(GrabiColor.brandStrong)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(GrabiColor.surface)
            .overlay(Capsule().strokeBorder(GrabiColor.borderStrong, lineWidth: 1.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .grabiFocusRing(Capsule())
        .accessibilityLabel(String(format: L("ui.a11y.paused"), elapsed))
    }
}

/// Circular button on the pill (pause: outline; stop: rec fill).
struct PillCircleButton: View {
    enum Kind { case pause, stop, resume }
    let kind: Kind
    let action: () -> Void
    var size: CGFloat = 32

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                switch kind {
                case .pause:
                    GrabiIconView(.pause, size: size * 0.44, tint: GrabiColor.ivoryFixed)
                        .frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(GrabiColor.inkFixedBorder, lineWidth: 1.5))
                case .stop:
                    RoundedRectangle(cornerRadius: 2)
                        .fill(GrabiColor.inkFixed)
                        .frame(width: size * 0.31, height: size * 0.31)
                        .frame(width: size, height: size)
                        .background(Circle().fill(GrabiColor.recOnInk))
                case .resume:
                    GrabiIconView(.resume, size: size * 0.4, tint: GrabiColor.inkFixed)
                        .frame(width: size, height: size)
                        .background(Circle().fill(GrabiColor.ivoryFixed))
                }
            }
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
        .accessibilityLabel(kind == .pause ? L("ui.pause") : kind == .stop ? L("ui.stop") : L("ui.resume"))
    }
}

/// Floating pill during recording (Phase 3 §03): minimal, draggable,
/// always on top, excluded from capture. Double-click collapses it.
public struct FloatingPill: View {
    let isPaused: Bool
    let elapsed: String
    @Binding var collapsed: Bool
    /// Optional live controls: (on state, tap action).
    let cameraToggle: (isOn: Bool, action: () -> Void)?
    let micToggle: (isOn: Bool, action: () -> Void)?
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void

    public init(isPaused: Bool,
                elapsed: String,
                collapsed: Binding<Bool>,
                cameraToggle: (isOn: Bool, action: () -> Void)? = nil,
                micToggle: (isOn: Bool, action: () -> Void)? = nil,
                onPause: @escaping () -> Void,
                onResume: @escaping () -> Void,
                onStop: @escaping () -> Void) {
        self.isPaused = isPaused
        self.elapsed = elapsed
        self._collapsed = collapsed
        self.cameraToggle = cameraToggle
        self.micToggle = micToggle
        self.onPause = onPause
        self.onResume = onResume
        self.onStop = onStop
    }

    public var body: some View {
        HStack(spacing: 13) {
            if !collapsed {
                DragHandleDots()
            }
            Group {
                if isPaused {
                    RoundedRectangle(cornerRadius: 2.5).fill(GrabiColor.ambarOnInk)
                } else {
                    SemaforoDot(.recording, size: 11)
                }
            }
            .frame(width: 11, height: 11)
            Text(elapsed)
                .font(GrabiFont.timer(collapsed ? 13 : 17))
                .foregroundStyle(isPaused ? GrabiColor.ivoryFixedDim : GrabiColor.ivoryFixed)
            if !collapsed {
                Rectangle().fill(GrabiColor.inkFixedSoft).frame(width: 1, height: 22)
                if let cameraToggle {
                    PillSourceToggle(icon: .camCircle, isOn: cameraToggle.isOn,
                                     onLabel: L("ui.cam.hide"), offLabel: L("ui.cam.show"),
                                     action: cameraToggle.action)
                }
                if let micToggle {
                    PillSourceToggle(icon: .microphone, isOn: micToggle.isOn,
                                     onLabel: L("ui.mic.mute"), offLabel: L("ui.mic.unmute"),
                                     action: micToggle.action)
                }
                if isPaused {
                    Button(action: onResume) {
                        HStack(spacing: 7) {
                            GrabiIconView(.resume, size: 12, tint: GrabiColor.inkFixed)
                            Text(L("ui.resume"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GrabiColor.inkFixed)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(GrabiColor.ivoryFixed))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("ui.resume"))
                } else {
                    PillCircleButton(kind: .pause, action: onPause, size: 30)
                }
                PillCircleButton(kind: .stop, action: onStop, size: 30)
            }
        }
        .padding(.leading, collapsed ? 14 : 12)
        .padding(.trailing, collapsed ? 14 : 18)
        .padding(.vertical, collapsed ? 6 : 10)
        .background(GrabiColor.inkFixed.opacity(0.92))
        .clipShape(Capsule())
        .grabiShadow(.e3)
        .onTapGesture(count: 2) {
            withAnimation(GrabiAnimation.standard()) { collapsed.toggle() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: isPaused ? L("ui.a11y.pillPause") : L("ui.a11y.recording"), elapsed))
    }
}

/// Drag handle (6 dots), visible on the pill.
struct DragHandleDots: View {
    var body: some View {
        VStack(spacing: 3.5) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 4.5) {
                    Circle().frame(width: 3.2, height: 3.2)
                    Circle().frame(width: 3.2, height: 3.2)
                }
            }
        }
        .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0x5C/255.0, green: 0x55/255.0, blue: 0x48/255.0, alpha: 1)))
        .accessibilityHidden(true)
    }
}


/// Source toggle on the pill (live camera/mic): on = ivory icon with
/// outline; off = dimmed icon with an amber diagonal bar (traffic-light
/// semantics: amber = paused, not error).
struct PillSourceToggle: View {
    let icon: GrabiIcon
    let isOn: Bool
    let onLabel: String
    let offLabel: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                GrabiIconView(icon, size: 14, tint: isOn ? GrabiColor.ivoryFixed : GrabiColor.ivoryFixedDim)
                if !isOn {
                    Rectangle()
                        .fill(GrabiColor.ambarOnInk)
                        .frame(width: 22, height: 2.5)
                        .rotationEffect(.degrees(-45))
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(
                isOn ? GrabiColor.inkFixedBorder : GrabiColor.ambarOnInk.opacity(0.6),
                lineWidth: 1.5))
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
        .help(isOn ? onLabel : offLabel)
        .accessibilityLabel(isOn ? onLabel : offLabel)
    }
}
