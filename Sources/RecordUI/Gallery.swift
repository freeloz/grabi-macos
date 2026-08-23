import SwiftUI
import RecordEngine
import GrabiDomain

/// Internal gallery (debug only): every component in all of its states,
/// to verify fidelity against the prototype before assembling screens.
public struct GrabiGallery: View {
    @State private var scheme: ColorScheme = .light
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var shape: CameraShape = .circle
    @State private var capture = "screen"
    @State private var pillCollapsed = false
    @State private var level: Double = 0.4

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrabiSpace.s8) {
                header

                section("Mascot — manual poses") {
                    HStack(spacing: GrabiSpace.s6) {
                        pose("Neutral", .neutral)
                        pose("Recording", .recording)
                        pose("Success", .success)
                        pose("Error", .error)
                        pose("Waving", .waving)
                        pose("Worried", .worried)
                    }
                    HStack(spacing: GrabiSpace.s6) {
                        VStack(spacing: 6) {
                            MascotView(pose: .ready, size: 76, bodyColor: GrabiColor.success, faceColor: GrabiColor.inkFixed)
                            caption("Traffic light · ready")
                        }
                        VStack(spacing: 6) {
                            MascotView(pose: .recording, size: 76)
                            caption("Traffic light · recording")
                        }
                        VStack(spacing: 6) {
                            MascotView(pose: .paused, size: 76, bodyColor: GrabiColor.ambarOnInk, faceColor: GrabiColor.inkFixed)
                            caption("Traffic light · paused")
                        }
                    }
                }

                section("Custom icons — 24 px, stroke 2") {
                    HStack(spacing: GrabiSpace.s4) {
                        ForEach(GrabiIcon.allCases, id: \.self) { icon in
                            VStack(spacing: 6) {
                                GrabiIconView(icon, size: 28)
                                    .padding(10)
                                    .background(GrabiColor.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                caption(icon.rawValue)
                            }
                        }
                    }
                }

                section("Buttons — variants and states") {
                    HStack(spacing: GrabiSpace.s3) {
                        GrabiButton("Record", kind: .primario) {}
                        GrabiButton("Share", kind: .secundario) {}
                        GrabiButton("Skip", kind: .fantasma) {}
                        GrabiButton("Discard", kind: .destructivo) {}
                        GrabiIconButton(.pause, help: "Pause") {}
                    }
                    HStack(spacing: GrabiSpace.s3) {
                        GrabiButton("Record", kind: .primario) {}.disabled(true)
                        GrabiButton("Saving…", kind: .primario, isLoading: true) {}
                        GrabiButton("Share", kind: .secundario) {}.disabled(true)
                    }
                }

                section("The record button ★ — traffic light") {
                    VStack(spacing: GrabiSpace.s3) {
                        RecordButton(state: .ready)
                        RecordButton(state: .ready).disabled(true)
                        RecordButton(state: .recording, elapsed: "12:34")
                        RecordButton(state: .paused, elapsed: "12:34")
                    }
                    .frame(width: 328)
                }

                section("Floating pill") {
                    HStack(spacing: GrabiSpace.s6) {
                        FloatingPill(isPaused: false, elapsed: "12:34", collapsed: .constant(false),
                                     onPause: {}, onResume: {}, onStop: {})
                        FloatingPill(isPaused: true, elapsed: "12:34", collapsed: .constant(false),
                                     onPause: {}, onResume: {}, onStop: {})
                        FloatingPill(isPaused: false, elapsed: "12:34", collapsed: $pillCollapsed,
                                     onPause: {}, onResume: {}, onStop: {})
                    }
                    caption("Double-click the third one to collapse/expand")
                }

                section("Source rows — all 4 states") {
                    SourceList {
                        SourceRow(icon: .screen, title: "Screen", subtitle: "Full screen · built-in",
                                  isOn: $toggleOn)
                        RowDivider()
                        SourceRow(icon: .camCircle, title: "Camera", subtitle: "Circle · bottom right",
                                  isOn: $toggleOn)
                        RowDivider()
                        SourceRow(icon: .microphone, title: "Microphone", subtitle: "MacBook Pro",
                                  status: .sinPermiso, isOn: $toggleOff, onPermissionTap: {})
                        RowDivider()
                        SourceRow(icon: .systemAudio, title: "System audio",
                                  subtitle: "Not available on this version of macOS",
                                  status: .noDisponible, isOn: $toggleOff)
                        RowDivider()
                        SourceRow(icon: .camCircle, title: "Camera", subtitle: "Permission granted! You can turn it on now",
                                  status: .celebracion, isOn: $toggleOff)
                        RowDivider()
                        SourceRow(icon: .microphone, title: "Microphone", subtitle: "MacBook Pro",
                                  isOn: $toggleOn, level: level)
                    }
                    .frame(width: 328)
                    Slider(value: $level, in: 0...1) { Text("Level") }
                        .frame(width: 200)
                }

                section("Segmented — capture and camera shape") {
                    GrabiSegmented(items: [
                        GrabiSegmentItem("screen", label: "Screen", icon: .screen),
                        GrabiSegmentItem("window", label: "Window", icon: .window),
                        GrabiSegmentItem("region", label: "Region", icon: .region),
                    ], selection: $capture)
                    .frame(width: 328)
                    GrabiSegmented(items: CameraShape.allCases.map {
                        GrabiSegmentItem($0, icon: .forShape($0))
                    }, selection: $shape)
                }

                section("Badges") {
                    HStack(spacing: GrabiSpace.s4) {
                        RecBadge(elapsed: "12:34")
                        StatusBadge(.ready, text: "Ready")
                        StatusBadge(.paused, text: "Paused")
                        StatusBadge(.duracion, text: "2:34")
                    }
                }

                section("Toasts") {
                    GrabiToast(title: "Done! Your recording is ready",
                               kind: .success(thumbnail: nil, meta: "2:34 · 1080p · 84 MB", actionLabel: "View", action: {}))
                        .frame(width: 420)
                    GrabiToast(title: "I couldn't save the file",
                               kind: .error(mensaje: "Disk space is running low. Your recording is still safe in memory.",
                                            actionLabel: "Retry", action: {}))
                        .frame(width: 420)
                }

                section("Modal — destructive decisions only") {
                    GrabiModal(title: "Discard the recording?",
                               message: "That's 12 minutes and 34 seconds. If you discard it, there's no way to get it back.",
                               safeLabel: "Keep", destructiveLabel: "Discard",
                               onSafe: {}, onDestructive: {})
                }

                section("Tooltip") {
                    HStack(spacing: GrabiSpace.s6) {
                        GrabiButton("Hover here", kind: .secundario) {}
                            .grabiTooltip("Record · ⌘⇧2")
                        GrabiIconButton(.camCircle, help: "Change shape") {}
                            .grabiTooltip("Change shape · right-click")
                    }
                    .padding(.top, GrabiSpace.s8)
                }
            }
            .padding(GrabiSpace.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GrabiColor.bg)
        .preferredColorScheme(scheme)
        .frame(minWidth: 820, minHeight: 600)
    }

    private var header: some View {
        HStack(spacing: GrabiSpace.s4) {
            MascotView(pose: .neutral, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Design system gallery")
                    .font(GrabiFont.title2)
                    .foregroundStyle(GrabiColor.text)
                Text("Fidelity check against design/ · debug only")
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
            }
            Spacer()
            Picker("Mode", selection: $scheme) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: GrabiSpace.s4) {
            Text(title)
                .font(GrabiFont.title3)
                .foregroundStyle(GrabiColor.text)
            content()
        }
    }

    private func pose(_ name: String, _ pose: MascotPose) -> some View {
        VStack(spacing: 6) {
            MascotView(pose: pose, size: 76)
            caption(name)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(GrabiColor.textSecondary)
    }
}
