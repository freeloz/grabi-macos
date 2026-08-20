import SwiftUI
import RecordEngine

/// Galería interna (solo debug): todos los componentes en todos sus estados,
/// para verificar fidelidad contra el prototipo antes de armar pantallas.
public struct GrabiGallery: View {
    @State private var scheme: ColorScheme = .light
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var shape: CameraShape = .circle
    @State private var capture = "pantalla"
    @State private var pillCollapsed = false
    @State private var level: Double = 0.4

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrabiSpace.s8) {
                header

                section("Mascota — poses del manual") {
                    HStack(spacing: GrabiSpace.s6) {
                        pose("Neutral", .neutral)
                        pose("Grabando", .grabando)
                        pose("Éxito", .exito)
                        pose("Error", .error)
                        pose("Saludando", .saludando)
                        pose("Preocupado", .preocupado)
                    }
                    HStack(spacing: GrabiSpace.s6) {
                        VStack(spacing: 6) {
                            MascotView(pose: .listo, size: 76, bodyColor: GrabiColor.exito, faceColor: GrabiColor.inkFixed)
                            caption("Semáforo · listo")
                        }
                        VStack(spacing: 6) {
                            MascotView(pose: .grabando, size: 76)
                            caption("Semáforo · grabando")
                        }
                        VStack(spacing: 6) {
                            MascotView(pose: .pausado, size: 76, bodyColor: GrabiColor.ambarOnInk, faceColor: GrabiColor.inkFixed)
                            caption("Semáforo · pausado")
                        }
                    }
                }

                section("Íconos custom — 24 px, trazo 2") {
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

                section("Botones — variantes y estados") {
                    HStack(spacing: GrabiSpace.s3) {
                        GrabiButton("Grabar", kind: .primario) {}
                        GrabiButton("Compartir", kind: .secundario) {}
                        GrabiButton("Omitir", kind: .fantasma) {}
                        GrabiButton("Descartar", kind: .destructivo) {}
                        GrabiIconButton(.pausa, help: "Pausar") {}
                    }
                    HStack(spacing: GrabiSpace.s3) {
                        GrabiButton("Grabar", kind: .primario) {}.disabled(true)
                        GrabiButton("Guardando…", kind: .primario, isLoading: true) {}
                        GrabiButton("Compartir", kind: .secundario) {}.disabled(true)
                    }
                }

                section("El botón de grabar ★ — semáforo") {
                    VStack(spacing: GrabiSpace.s3) {
                        RecordButton(state: .listo)
                        RecordButton(state: .listo).disabled(true)
                        RecordButton(state: .grabando, elapsed: "12:34")
                        RecordButton(state: .pausado, elapsed: "12:34")
                    }
                    .frame(width: 328)
                }

                section("Pastilla flotante") {
                    HStack(spacing: GrabiSpace.s6) {
                        FloatingPill(isPaused: false, elapsed: "12:34", collapsed: .constant(false),
                                     onPause: {}, onResume: {}, onStop: {})
                        FloatingPill(isPaused: true, elapsed: "12:34", collapsed: .constant(false),
                                     onPause: {}, onResume: {}, onStop: {})
                        FloatingPill(isPaused: false, elapsed: "12:34", collapsed: $pillCollapsed,
                                     onPause: {}, onResume: {}, onStop: {})
                    }
                    caption("Doble clic en la tercera para colapsar/expandir")
                }

                section("Filas de fuente — los 4 estados") {
                    SourceList {
                        SourceRow(icon: .pantalla, title: "Pantalla", subtitle: "Pantalla completa · integrada",
                                  isOn: $toggleOn)
                        RowDivider()
                        SourceRow(icon: .camCirculo, title: "Cámara", subtitle: "Círculo · abajo a la derecha",
                                  isOn: $toggleOn)
                        RowDivider()
                        SourceRow(icon: .microfono, title: "Micrófono", subtitle: "MacBook Pro",
                                  status: .sinPermiso, isOn: $toggleOff, onPermissionTap: {})
                        RowDivider()
                        SourceRow(icon: .audioSistema, title: "Audio del sistema",
                                  subtitle: "No disponible en esta versión de macOS",
                                  status: .noDisponible, isOn: $toggleOff)
                        RowDivider()
                        SourceRow(icon: .camCirculo, title: "Cámara", subtitle: "¡Permiso concedido! Ya puedes activarla",
                                  status: .celebracion, isOn: $toggleOff)
                        RowDivider()
                        SourceRow(icon: .microfono, title: "Micrófono", subtitle: "MacBook Pro",
                                  isOn: $toggleOn, level: level)
                    }
                    .frame(width: 328)
                    Slider(value: $level, in: 0...1) { Text("Nivel") }
                        .frame(width: 200)
                }

                section("Segmented — captura y forma de cámara") {
                    GrabiSegmented(items: [
                        GrabiSegmentItem("pantalla", label: "Pantalla", icon: .pantalla),
                        GrabiSegmentItem("ventana", label: "Ventana", icon: .ventana),
                        GrabiSegmentItem("region", label: "Región", icon: .region),
                    ], selection: $capture)
                    .frame(width: 328)
                    GrabiSegmented(items: CameraShape.allCases.map {
                        GrabiSegmentItem($0, icon: .forShape($0))
                    }, selection: $shape)
                }

                section("Badges") {
                    HStack(spacing: GrabiSpace.s4) {
                        RecBadge(elapsed: "12:34")
                        StatusBadge(.listo, text: "Listo")
                        StatusBadge(.pausado, text: "Pausado")
                        StatusBadge(.duracion, text: "2:34")
                    }
                }

                section("Toasts") {
                    GrabiToast(title: "¡Quedó! Tu grabación está lista",
                               kind: .exito(thumbnail: nil, meta: "2:34 · 1080p · 84 MB", actionLabel: "Ver", action: {}))
                        .frame(width: 420)
                    GrabiToast(title: "No pude guardar el archivo",
                               kind: .error(mensaje: "Queda poco espacio en disco. La grabación sigue a salvo en memoria.",
                                            actionLabel: "Reintentar", action: {}))
                        .frame(width: 420)
                }

                section("Modal — solo decisiones destructivas") {
                    GrabiModal(title: "¿Descartar la grabación?",
                               message: "Son 12 minutos y 34 segundos. Si la descartas, no hay forma de recuperarla.",
                               safeLabel: "Conservar", destructiveLabel: "Descartar",
                               onSafe: {}, onDestructive: {})
                }

                section("Tooltip") {
                    HStack(spacing: GrabiSpace.s6) {
                        GrabiButton("Pasa el cursor", kind: .secundario) {}
                            .grabiTooltip("Grabar · ⌘⇧2")
                        GrabiIconButton(.camCirculo, help: "Cambiar forma") {}
                            .grabiTooltip("Cambiar forma · clic derecho")
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
                Text("Galería del sistema de diseño")
                    .font(GrabiFont.title2)
                    .foregroundStyle(GrabiColor.text)
                Text("Verificación de fidelidad contra design/ · solo debug")
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
            }
            Spacer()
            Picker("Modo", selection: $scheme) {
                Text("Claro").tag(ColorScheme.light)
                Text("Oscuro").tag(ColorScheme.dark)
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
