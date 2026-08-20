import SwiftUI
import RecordEngine

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Grabar")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(RecordingSource.allCases) { source in
                    SourceToggleRow(model: model, source: source)
                }
            }

            targetPicker

            statusSection

            recordButton

            if model.isRecording || model.isPaused {
                Button {
                    model.togglePause()
                } label: {
                    Label(model.isPaused ? "Reanudar" : "Pausar",
                          systemImage: model.isPaused ? "play.circle" : "pause.circle")
                }
            }

            if case .stopped = model.engineState, model.lastRecordingURL != nil {
                Button {
                    model.showLastRecordingInFinder()
                } label: {
                    Label("Mostrar en Finder", systemImage: "folder")
                }
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(width: 380)
        .task {
            await model.refreshPreflight()
        }
        .confirmationDialog(
            "Algunas fuentes no están disponibles",
            isPresented: $model.showUnavailableDialog,
            titleVisibility: .visible
        ) {
            Button("Grabar sin: \(model.unavailableSources.map(\.displayName).joined(separator: ", "))") {
                model.startWithoutUnavailable()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(unavailableDetail)
        }
    }

    private var unavailableDetail: String {
        guard let report = model.preflight else { return "" }
        return model.unavailableSources
            .compactMap { source in
                guard let why = report.status(for: source).explanation else { return nil }
                return "\(source.displayName): \(why)"
            }
            .joined(separator: "\n\n")
    }

    // Selector de target provisional para probar FASE A (pantalla/ventana/región).
    private var targetPicker: some View {
        Picker("Capturar", selection: Binding(
            get: { model.selectedTarget },
            set: { model.selectedTarget = $0 }
        )) {
            ForEach(model.availableDisplays) { display in
                Text(display.isMain ? "Pantalla completa (\(display.name))" : display.name)
                    .tag(display.isMain ? CaptureTarget.mainDisplay : CaptureTarget.display(display.id))
            }
            if model.availableDisplays.isEmpty {
                Text("Pantalla completa").tag(CaptureTarget.mainDisplay)
            }
            Text("Región (centro 800×500)").tag(CaptureTarget.region(
                displayID: nil,
                rect: CGRect(x: 200, y: 150, width: 800, height: 500)))
            ForEach(model.availableWindows.prefix(10)) { window in
                Text("Ventana: \(window.appName) — \(window.title.prefix(30))")
                    .tag(CaptureTarget.window(window.id))
            }
        }
        .disabled(model.isBusy)
        .task { await model.refreshContent() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshContent() }
        }
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            switch model.engineState {
            case .idle, .stopped:
                Circle().fill(.gray).frame(width: 10, height: 10)
                Text(model.lastRecordingURL == nil ? "Listo para grabar" : "Grabación guardada")
            case .starting:
                ProgressView().controlSize(.small)
                Text("Iniciando…")
            case .recording:
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("Grabando")
                Spacer()
                Text(AppModel.formatElapsed(model.elapsed))
                    .font(.system(.title3, design: .monospaced))
            case .paused:
                Circle().fill(.orange).frame(width: 10, height: 10)
                Text("En pausa")
            case .stopping:
                ProgressView().controlSize(.small)
                Text("Guardando…")
            case .failed:
                Circle().fill(.orange).frame(width: 10, height: 10)
                Text("Error")
            }
            if !model.isRecording { Spacer() }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            Label(
                model.isRecording ? "Detener" : "Iniciar grabación",
                systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
            .font(.title3.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.isRecording ? .red : .accentColor)
        .disabled(!model.anySourceEnabled || (model.isBusy && !model.isRecording))
        .keyboardShortcut(.defaultAction)
    }
}

/// Fila de una fuente: toggle + aviso visual con explicación si no es usable.
private struct SourceToggleRow: View {
    @ObservedObject var model: AppModel
    let source: RecordingSource

    private var status: SourceStatus? {
        model.preflight?.status(for: source)
    }

    private var icon: String {
        switch source {
        case .screen: return "rectangle.on.rectangle"
        case .camera: return "web.camera"
        case .microphone: return "mic"
        case .systemAudio: return "speaker.wave.2"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { model.isEnabled(source) },
                set: { model.setEnabled(source, $0) }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .frame(width: 20)
                    Text(source.displayName)
                    if let status, !status.isUsable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(status.explanation ?? "")
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(model.isBusy)

            if let status, !status.isUsable, let why = status.explanation {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if source == .screen || source == .systemAudio {
                    Button("Abrir Ajustes de Grabación de Pantalla") {
                        model.openScreenRecordingSettings()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
