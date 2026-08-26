import SwiftUI
import AppKit
import CoreVideo
import RecordEngine
import RecordUI
import GrabiDomain

enum MainTab: String, CaseIterable, Identifiable {
    case record, library, settings
    var id: String { rawValue }
}

/// Grabi's main window (Phase 6): the app stops living only in the menu bar
/// and becomes a normal Mac app — Dock icon, menu bar of its own, and one
/// window that holds everything: recording, the library and settings.
/// The menu bar item stays as optional quick access.
@MainActor
final class MainWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    let renderView = PixelBufferNSView()
    /// Size of the last frame (to map the camera overlay onto the video).
    @Published var videoSize = CGSize(width: 16, height: 10)
    @Published var tab: MainTab = .record
    private weak var model: GrabiAppModel?

    var isVisible: Bool { window?.isVisible ?? false }
    /// The preview only runs when it is actually on screen: minimized or
    /// fully covered by another window, capturing would be wasted work.
    var showsPreview: Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        // Occlusion is only trusted once macOS has actually told us the
        // window got covered: polling occlusionState right after ordering a
        // window front reports "not visible" and would silently kill the
        // preview on launch.
        return tab == .record && !isCovered
    }

    /// Set from the occlusion notification, never polled.
    private var isCovered = false

    func show(model: GrabiAppModel, tab: MainTab? = nil) {
        self.model = model
        if let tab { self.tab = tab }
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = L("app.window.title")
            win.titlebarAppearsTransparent = true
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.minSize = NSSize(width: 860, height: 600)
            win.contentView = NSHostingView(rootView: MainWindowRoot(model: model, controller: self))
            win.center()
            // Restores position/size across launches — but a frame saved on a
            // display that is gone (or rearranged) can land off-screen, which
            // looks exactly like "the app doesn't open".
            win.setFrameAutosaveName("GrabiMainWindow")
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(win.frame) }) {
                win.center()
            }
            window = win
        }
        Self.dismissMenuBarPanel()
        window?.makeKeyAndOrderFront(nil)
        // Nothing steals focus on open: the ring belongs to keyboard users
        // who tab into a control, not to whoever opens the window.
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.mainWindowShown()
    }

    /// The menu bar panel is a floating window of its own: opening the main
    /// window from it must put it away, or it stays hanging over the app.
    static func dismissMenuBarPanel() {
        for window in NSApp.windows
        where String(describing: type(of: window)).contains("MenuBarExtra")
            || String(describing: type(of: window)).contains("StatusBar") {
            window.orderOut(nil)
        }
    }

    func receive(_ pixelBuffer: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        if size != videoSize { videoSize = size }
        renderView.render(pixelBuffer)
    }

    func windowWillClose(_ notification: Notification) {
        model?.mainWindowClosed()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        isCovered = !(window?.occlusionState.contains(.visible) ?? true)
        model?.updateCapture()
    }

    func windowDidMiniaturize(_ notification: Notification) { model?.updateCapture() }
    func windowDidDeminiaturize(_ notification: Notification) { model?.updateCapture() }
}

// MARK: - Root

struct MainWindowRoot: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject var controller: MainWindowController
    /// Observed explicitly: it is a store of its own, and the sidebar count,
    /// the recents strip and the grid all read from it.
    @ObservedObject private var library: LibraryStore

    init(model: GrabiAppModel, controller: MainWindowController) {
        self.model = model
        self.controller = controller
        self.library = model.library
    }

    var body: some View {
        Group {
            if model.onboardingDone {
                appBody
            } else {
                // First run: the welcome and the permissions live INSIDE the
                // window (Phase 6) instead of in a separate window.
                OnboardingView(model: model, onFinish: { startRecording in
                    model.finishWelcome(startRecording: startRecording)
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(GrabiColor.bg)
        .onChange(of: controller.tab) { _ in model.updateCapture() }
    }

    private var appBody: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, controller: controller, library: library)
            Divider().overlay(GrabiColor.border)
            Group {
                switch controller.tab {
                case .record: RecordPanel(model: model, controller: controller, library: library)
                case .library: LibraryPanel(model: model, controller: controller, library: library, cloud: model.cloud)
                case .settings: SettingsPanel(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject var controller: MainWindowController
    @ObservedObject var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: GrabiSpace.s1) {
            HStack(spacing: GrabiSpace.s2) {
                MascotView(pose: .ready, size: 26)
                Text("Grabi")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(GrabiColor.text)
            }
            .padding(.horizontal, GrabiSpace.s2)
            .padding(.top, GrabiSpace.s2)
            .padding(.bottom, GrabiSpace.s3)

            navItem(.record, icon: .record, title: L("app.nav.record"))
            navItem(.library, icon: .folder, title: L("app.nav.library"),
                    badge: library.items.isEmpty ? nil : "\(library.items.count)")
            navItem(.settings, icon: .settings, title: L("app.nav.settings"))

            Spacer(minLength: GrabiSpace.s4)

            // The mascot tells you, in one line, whether you can record.
            HStack(alignment: .top, spacing: 9) {
                MascotView(pose: model.statusPose, size: 30)
                Text(model.statusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(GrabiColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GrabiColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(GrabiColor.border, lineWidth: 1))
        }
        .padding(GrabiSpace.s3)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(GrabiColor.sidebar)
    }

    private func navItem(_ tab: MainTab, icon: GrabiIcon, title: String, badge: String? = nil) -> some View {
        let selected = controller.tab == tab
        return Button {
            controller.tab = tab
        } label: {
            HStack(spacing: 10) {
                GrabiIconView(icon, size: 15, tint: selected ? GrabiColor.text : GrabiColor.textSecondary)
                Text(title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? GrabiColor.text : GrabiColor.textSecondary)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GrabiColor.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? GrabiColor.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .shadow(color: selected ? GrabiColor.shadow : .clear, radius: 3, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Record panel

private struct RecordPanel: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject var controller: MainWindowController
    @ObservedObject var library: LibraryStore

    var body: some View {
        VStack(spacing: GrabiSpace.s3) {
            preview
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: GrabiSpace.s3) {
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

                Button(L("app.change")) {
                    // Region draws a new region; screen and window open the
                    // visual picker. Same behavior as the menu bar panel.
                    if model.captureMode == .region {
                        model.pickRegion()
                    } else {
                        model.pickCaptureSource()
                    }
                }
                .buttonStyle(.plain)
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.brandStrong)
                .disabled(model.isActive)

                Spacer(minLength: GrabiSpace.s2)

                GrabiSegmented(items: CameraShape.allCases.map {
                    GrabiSegmentItem($0, icon: .forShape($0))
                }, selection: Binding(
                    get: { model.cameraLayout.shape },
                    set: { model.cameraLayout.shape = $0 }
                ))
                .disabled(!model.cameraEnabled)
            }

            SourceCards(model: model, levels: model.levels)

            if !library.items.isEmpty {
                recents
            }

            RecordButton(
                state: model.recordButtonState,
                elapsed: model.elapsedText,
                height: 52,
                onRecord: { model.requestStart() },
                onPause: { model.togglePause() },
                onResume: { model.togglePause() },
                onStop: { Task { await model.stop() } })
                .disabled(!model.anySourceEnabled && !model.isActive)
        }
        .padding(GrabiSpace.s4)
    }

    @ViewBuilder
    private var preview: some View {
        if model.screenEnabled || model.cameraEnabled {
            LivePreview(model: model, renderView: controller.renderView, videoSize: controller.videoSize)
        } else {
            VStack(spacing: GrabiSpace.s3) {
                MascotView(pose: .waving, size: 72)
                Text(L("app.preview.needSource"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GrabiColor.text)
                Text(L("app.preview.needSource.sub"))
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GrabiColor.sidebar)
        }
    }

    private var recents: some View {
        HStack(spacing: 9) {
            Text(L("app.library.recents"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GrabiColor.textSecondary)
            ForEach(library.items.prefix(3)) { item in
                Button { model.showMainWindow(tab: .library) } label: {
                    Thumbnail(item: item, width: 74, height: 44, showsNewBadge: false)
                }
                .buttonStyle(.plain)
                .help(item.name)
            }
            Spacer(minLength: 0)
            Button(L("app.library.seeAll")) { model.showMainWindow(tab: .library) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GrabiColor.brandStrong)
        }
    }
}


/// The four source rows. Their own view because the level meters update
/// several times a second: this is the only part that redraws with them.
private struct SourceCards: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject var levels: AudioLevels

    var body: some View {
            HStack(alignment: .top, spacing: GrabiSpace.s3) {
            SourceList {
                SourceRow(icon: .screen, title: RecordingSource.screen.displayName,
                          subtitle: model.captureLabel,
                          status: model.status(for: .screen),
                          isOn: Binding(get: { model.screenEnabled }, set: { model.screenEnabled = $0 }),
                          onPermissionTap: { model.openPermissionFlow(for: .screen) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .forShape(model.cameraLayout.shape),
                          title: RecordingSource.camera.displayName,
                          subtitle: model.cameraRowSubtitle,
                          status: model.status(for: .camera),
                          isOn: Binding(get: { model.cameraEnabled }, set: { model.cameraEnabled = $0 }),
                          onPermissionTap: { model.openPermissionFlow(for: .camera) })
                    .disabled(model.isActive)
            }
            SourceList {
                SourceRow(icon: .microphone, title: RecordingSource.microphone.displayName,
                          subtitle: model.micDeviceName,
                          status: model.status(for: .microphone),
                          isOn: Binding(get: { model.micEnabled }, set: { model.micEnabled = $0 }),
                          level: levels.microphone,
                          onPermissionTap: { model.openPermissionFlow(for: .microphone) })
                    .disabled(model.isActive)
                RowDivider()
                SourceRow(icon: .systemAudio, title: RecordingSource.systemAudio.displayName,
                          subtitle: model.systemAudioEnabled ? L("app.on") : L("app.off"),
                          status: model.status(for: .systemAudio),
                          isOn: Binding(get: { model.systemAudioEnabled }, set: { model.systemAudioEnabled = $0 }),
                          level: levels.system,
                          onPermissionTap: { model.openPermissionFlow(for: .systemAudio) })
                    .disabled(model.isActive)
            }
        }
    }
}

// MARK: - Library panel

private struct LibraryPanel: View {
    @ObservedObject var model: GrabiAppModel
    @ObservedObject var controller: MainWindowController
    @ObservedObject var library: LibraryStore
    @ObservedObject var cloud: CloudStore
    @State private var pendingDelete: RecordingItem?
    @State private var showCloudSheet = false

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: GrabiSpace.s3)]

    var body: some View {
        VStack(spacing: 0) {
            if library.items.isEmpty {
                empty
            } else {
                header
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: GrabiSpace.s4) {
                        ForEach(library.items) { item in
                            card(item)
                        }
                    }
                    .padding(GrabiSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GrabiColor.bg)
        .task {
            model.refreshLibrary()
            cloud.refreshAccount()
        }
        .sheet(isPresented: $showCloudSheet) { CloudSheet(store: cloud) }
        .confirmationDialog(
            L("app.library.deleteTitle"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("app.library.delete"), role: .destructive) {
                if let item = pendingDelete { library.trash(item) }
                pendingDelete = nil
            }
            Button(L("app.library.keep"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(LF("app.library.deleteMessage", pendingDelete?.name ?? ""))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L("app.library.title"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GrabiColor.text)
            Text(library.metaText)
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.textSecondary)
            Spacer(minLength: 0)
            Button(L("app.openFolder")) { model.openRecordingsFolder() }
                .buttonStyle(.plain)
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.brandStrong)
        }
        .padding(.horizontal, GrabiSpace.s4)
        .padding(.vertical, GrabiSpace.s3)
        .background(GrabiColor.bg)
    }

    private var empty: some View {
        VStack(spacing: GrabiSpace.s3) {
            MascotView(pose: .waving, size: 76)
            Text(L("app.library.empty.title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(GrabiColor.text)
            Text(L("app.library.empty.sub"))
                .font(GrabiFont.body)
                .foregroundStyle(GrabiColor.textSecondary)
            GrabiButton(L("app.library.empty.cta"), kind: .primario) {
                controller.tab = .record
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ item: RecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { library.play(item) } label: {
                Thumbnail(item: item, width: nil, height: 128,
                          showsNewBadge: library.newestURL == item.id)
            }
            .buttonStyle(.plain)

            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GrabiColor.text)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 7) {
                Text("\(item.whenText) · \(item.sizeText)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(GrabiColor.textSecondary)
                Spacer(minLength: 0)
                cloudAction(item)
                action("play.fill", help: L("app.library.play")) { library.play(item) }
                action("folder", help: L("app.library.finder")) { library.revealInFinder(item) }
                action("doc.on.doc", help: L("app.library.copy")) { library.copy(item) }
                Button {
                    pendingDelete = item
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundStyle(GrabiColor.error)
                }
                .buttonStyle(.plain)
                .help(L("app.library.delete"))
            }
        }
    }

    private func action(_ symbol: String, help: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 11.5))
                .foregroundStyle(GrabiColor.textSecondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The cloud action cycles with the share: icon → progress → check
    /// ("link copied") → back. Errors explain themselves on hover and
    /// dismiss on click.
    @ViewBuilder
    private func cloudAction(_ item: RecordingItem) -> some View {
        switch cloud.shares[item.id] {
        case .working(let stage):
            ProgressView(value: stage.fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .help(stage.helpText)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(GrabiColor.success)
                .help(L("app.cloud.linkCopied"))
        case .failed(let error):
            Button { cloud.dismissFailure(item) } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(GrabiColor.advertencia)
            }
            .buttonStyle(.plain)
            .help(error.userMessage)
        case nil:
            action("icloud.and.arrow.up", help: L("app.cloud.share")) {
                if cloud.account == nil { showCloudSheet = true } else { cloud.share(item) }
            }
        }
    }
}

private extension CloudShareStage {
    var fraction: Double {
        switch self {
        case .exporting(let p): return p * 0.4
        case .uploading(let p): return 0.4 + p * 0.55
        case .finishing: return 0.97
        }
    }

    var helpText: String {
        switch self {
        case .exporting: return L("app.cloud.exporting")
        case .uploading(let p): return LF("app.cloud.uploading", Int(p * 100))
        case .finishing: return L("app.cloud.finishing")
        }
    }
}

/// Recording thumbnail with its duration (and the NEW badge when it is the
/// one just recorded).
private struct Thumbnail: View {
    let item: RecordingItem
    let width: CGFloat?
    let height: CGFloat
    let showsNewBadge: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = item.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    GrabiColor.sidebar
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : width)
            .clipped()

            Text(item.durationText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(6)

            if showsNewBadge {
                Text(L("app.library.new"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GrabiColor.brandStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(showsNewBadge ? GrabiColor.brandStrong : GrabiColor.border,
                              lineWidth: showsNewBadge ? 2 : 1))
    }
}

// MARK: - Settings panel (the same settings, inside the window)

private struct SettingsPanel: View {
    @ObservedObject var model: GrabiAppModel
    private let gallery = GalleryWindowController()

    var body: some View {
        ScrollView {
            SettingsView(model: model, gallery: gallery)
                .frame(maxWidth: 560)
                .padding(.vertical, GrabiSpace.s2)
                .frame(maxWidth: .infinity)
        }
    }
}
