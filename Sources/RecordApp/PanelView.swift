import SwiftUI
import RecordEngine
import RecordUI

/// Menu bar panel (Phase 3 §01): the 5-second test.
/// What gets captured at the top, which sources go into it in the middle,
/// one single big button at the bottom. Fixed width 360.
struct PanelView: View {
    @ObservedObject var model: GrabiAppModel

    var body: some View {
        VStack(spacing: 14) {
            GrabiSegmented(items: [
                GrabiSegmentItem(CaptureMode.screen, label: L("app.seg.screen"), icon: .screen),
                GrabiSegmentItem(CaptureMode.window, label: L("app.seg.window"), icon: .window),
                GrabiSegmentItem(CaptureMode.region, label: L("app.seg.region"), icon: .region),
            ], selection: Binding(
                get: { model.captureMode },
                set: { newMode in
                    model.captureMode = newMode
                    if newMode == .region, model.regionRect == nil { model.pickRegion() }
                    if newMode == .window, model.selectedWindow == nil { model.pickCaptureSource() }
                }
            ))
            .disabled(model.isActive)

            targetDetail

            SourceList {
                SourceRow(icon: .screen, title: RecordingSource.screen.displayName, subtitle: model.captureLabel,
                          status: model.status(for: .screen),
                          isOn: Binding(get: { model.screenEnabled }, set: { model.screenEnabled = $0 }),
                          onPermissionTap: { model.openPermissionFlow(for: .screen) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .forShape(model.cameraLayout.shape), title: RecordingSource.camera.displayName, subtitle: model.cameraRowSubtitle,
                          status: model.status(for: .camera),
                          isOn: Binding(get: { model.cameraEnabled }, set: { model.cameraEnabled = $0 }),
                          onPermissionTap: { model.openPermissionFlow(for: .camera) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .microphone, title: RecordingSource.microphone.displayName, subtitle: model.micDeviceName,
                          status: model.status(for: .microphone),
                          isOn: Binding(get: { model.micEnabled }, set: { model.micEnabled = $0 }),
                          level: model.micLevel,
                          onPermissionTap: { model.openPermissionFlow(for: .microphone) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .systemAudio, title: RecordingSource.systemAudio.displayName,
                          subtitle: model.systemAudioEnabled ? L("app.on") : L("app.off"),
                          status: model.status(for: .systemAudio),
                          isOn: Binding(get: { model.systemAudioEnabled }, set: { model.systemAudioEnabled = $0 }),
                          level: model.systemLevel,
                          onPermissionTap: { model.openPermissionFlow(for: .systemAudio) })
                    .disabled(model.isActive)
            }

            RecordButton(
                state: recordButtonState,
                elapsed: model.elapsedText,
                height: 52,
                onRecord: { model.requestStart() },
                onPause: { model.togglePause() },
                onResume: { model.togglePause() },
                onStop: { Task { await model.stop() } })
                .disabled(!model.anySourceEnabled && !model.isActive)

            if let message = model.errorMessage {
                Text(message)
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(GrabiColor.bg)
        .onAppear { model.panelAppeared() }
        .onDisappear { model.panelDisappeared() }
        .confirmationDialog(
            L("app.dialog.sources.title"),
            isPresented: $model.showUnavailableDialog,
            titleVisibility: .visible
        ) {
            Button(LF("app.dialog.recordWithout", model.unavailableSources.map(\.displayName).joined(separator: ", "))) {
                model.startWithoutUnavailable()
            }
            Button(L("app.cancel"), role: .cancel) {}
        } message: {
            Text(model.unavailableSources
                .compactMap { model.preflight?.status(for: $0).explanation }
                .joined(separator: "\n\n"))
        }
    }

    private var recordButtonState: RecordButtonState {
        switch model.engineState {
        case .recording, .starting, .stopping: return .recording
        case .paused: return .paused
        default: return .ready
        }
    }

    /// Secondary picker per mode: display (if there are several), window, or region.
    @ViewBuilder
    private var targetDetail: some View {
        switch model.captureMode {
        case .screen:
            if model.availableDisplays.count > 1 {
                changeRow(label: model.captureLabel)
            }
        case .window:
            changeRow(label: model.captureLabel)
        case .region:
            HStack(spacing: GrabiSpace.s2) {
                Text(model.captureLabel)
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
                Spacer()
                Button(L("app.change")) { model.pickRegion() }
                    .font(GrabiFont.caption)
                    .buttonStyle(.link)
                    .tint(GrabiColor.brandStrong)
            }
            .padding(.horizontal, 4)
        }
    }

    /// Selection row with "Change…" that opens the visual thumbnail
    /// picker (displays and windows).
    private func changeRow(label: String) -> some View {
        HStack(spacing: GrabiSpace.s2) {
            Text(label)
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.textSecondary)
                .lineLimit(1)
            Spacer()
            Button(L("app.change")) { model.pickCaptureSource() }
                .font(GrabiFont.caption)
                .buttonStyle(.link)
                .tint(GrabiColor.brandStrong)
        }
        .padding(.horizontal, 4)
        .disabled(model.isActive)
    }

    private var footer: some View {
        HStack {
            Button(L("app.openWindow")) { model.showMainWindow() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GrabiColor.brandStrong)
            Spacer()
            HStack(spacing: 14) {
                Button { model.openRecordingsFolder() } label: {
                    GrabiIconView(.folder, size: 16, tint: GrabiColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L("app.openFolder"))
                Button { model.settingsController.show(model: model) } label: {
                    GrabiIconView(.settings, size: 16, tint: GrabiColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L("app.settings"))
                Rectangle()
                    .fill(GrabiColor.border)
                    .frame(width: 1, height: 14)
                Button(L("app.quit")) { model.quit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(GrabiColor.textSecondary)
                    .help(L("app.quit.help"))
                    .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Menu bar label: monochrome template when idle; colored dot + stopwatch
/// while recording (honesty: always visible).
struct MenuBarLabel: View {
    @ObservedObject var model: GrabiAppModel

    var body: some View {
        if model.isActive {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarIcons.coloredDot(paused: model.isPaused))
                Text(model.elapsedText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        } else {
            Image(nsImage: MenuBarIcons.templateRing)
        }
    }
}

enum MenuBarIcons {
    /// The dot with a ring, as a system template.
    static let templateRing: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setStrokeColor(.black)
            ctx.setLineWidth(1.8)
            ctx.strokeEllipse(in: rect.insetBy(dx: 2.5, dy: 2.5))
            ctx.setFillColor(.black)
            ctx.fillEllipse(in: rect.insetBy(dx: 6.2, dy: 6.2))
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func coloredDot(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            if paused {
                ctx.setFillColor(CGColor(red: 0xE4/255.0, green: 0xB4/255.0, blue: 0x5C/255.0, alpha: 1))
                let r = rect.insetBy(dx: 2.5, dy: 2.5)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()
            } else {
                ctx.setFillColor(CGColor(red: 0xE5/255.0, green: 0x48/255.0, blue: 0x3F/255.0, alpha: 1))
                ctx.fillEllipse(in: rect.insetBy(dx: 2.5, dy: 2.5))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
