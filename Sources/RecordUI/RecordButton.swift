import SwiftUI

/// El botón de grabar ★ (Fase 2 §03). Sigue el semáforo y, al grabar, SE
/// TRANSFORMA en el cronómetro: mismo lugar, misma forma, otro trabajo.
/// Radio full; altura 56 por defecto (52 dentro del panel, Fase 3 §01).
public enum RecordButtonState: Equatable {
    case listo
    case grabando
    case pausado
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
            case .listo: listoBody
            case .grabando: grabandoBody
            case .pausado: pausadoBody
            }
        }
        .frame(height: height)
        .animation(GrabiAnimation.standard(), value: state)
    }

    // listo · punto verde + Grabar + atajo. Hover: elev.1 → elev.2.
    private var listoBody: some View {
        Button(action: onRecord) {
            HStack(spacing: GrabiSpace.s3) {
                SemaforoDot(isEnabled ? .listo : .apagado, size: 14)
                Text(L("ui.grabar"))
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
                    isEnabled ? (hovering ? GrabiColor.switchOff /* #C4B89F, hover del spec */ : GrabiColor.borderStrong)
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
        .accessibilityLabel(L("ui.grabar"))
        .keyboardShortcut(.defaultAction)
    }

    // grabando · pastilla oscura con cronómetro + pausa + stop.
    private var grabandoBody: some View {
        HStack(spacing: GrabiSpace.s3 + 2) {
            SemaforoDot(.grabando, size: 13)
            Text(elapsed)
                .font(GrabiFont.timer())
                .foregroundStyle(GrabiColor.ivoryFixed)
            Rectangle()
                .fill(GrabiColor.inkFixedSoft)
                .frame(width: 1, height: 24)
            PillCircleButton(kind: .pausa, action: onPause)
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
        .accessibilityLabel(String(format: L("ui.a11y.grabando"), elapsed))
    }

    // pausado · ámbar + cronómetro atenuado + Reanudar.
    private var pausadoBody: some View {
        Button(action: onResume) {
            HStack(spacing: GrabiSpace.s3 + 2) {
                SemaforoDot(.pausado, size: 13)
                Text(elapsed)
                    .font(GrabiFont.timer())
                    .foregroundStyle(GrabiColor.textSecondary)
                Text(L("ui.reanudar"))
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
        .accessibilityLabel(String(format: L("ui.a11y.pausado"), elapsed))
    }
}

/// Botón circular de la pastilla (pausa: borde; stop: relleno rec).
struct PillCircleButton: View {
    enum Kind { case pausa, stop, reanudar }
    let kind: Kind
    let action: () -> Void
    var size: CGFloat = 32

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                switch kind {
                case .pausa:
                    GrabiIconView(.pausa, size: size * 0.44, tint: GrabiColor.ivoryFixed)
                        .frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(GrabiColor.inkFixedBorder, lineWidth: 1.5))
                case .stop:
                    RoundedRectangle(cornerRadius: 2)
                        .fill(GrabiColor.inkFixed)
                        .frame(width: size * 0.31, height: size * 0.31)
                        .frame(width: size, height: size)
                        .background(Circle().fill(GrabiColor.recOnInk))
                case .reanudar:
                    GrabiIconView(.reanudar, size: size * 0.4, tint: GrabiColor.inkFixed)
                        .frame(width: size, height: size)
                        .background(Circle().fill(GrabiColor.ivoryFixed))
                }
            }
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
        .accessibilityLabel(kind == .pausa ? L("ui.pausar") : kind == .stop ? L("ui.detener") : L("ui.reanudar"))
    }
}

/// Pastilla flotante durante la grabación (Fase 3 §03): mínima, arrastrable,
/// siempre encima, excluida de la captura. Doble clic la colapsa.
public struct FloatingPill: View {
    let isPaused: Bool
    let elapsed: String
    @Binding var collapsed: Bool
    /// Controles en vivo opcionales: (encendido, acción al pulsar).
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
                    SemaforoDot(.grabando, size: 11)
                }
            }
            .frame(width: 11, height: 11)
            Text(elapsed)
                .font(GrabiFont.timer(collapsed ? 13 : 17))
                .foregroundStyle(isPaused ? GrabiColor.ivoryFixedDim : GrabiColor.ivoryFixed)
            if !collapsed {
                Rectangle().fill(GrabiColor.inkFixedSoft).frame(width: 1, height: 22)
                if let cameraToggle {
                    PillSourceToggle(icon: .camCirculo, isOn: cameraToggle.isOn,
                                     onLabel: L("ui.cam.ocultar"), offLabel: L("ui.cam.mostrar"),
                                     action: cameraToggle.action)
                }
                if let micToggle {
                    PillSourceToggle(icon: .microfono, isOn: micToggle.isOn,
                                     onLabel: L("ui.mic.silenciar"), offLabel: L("ui.mic.activar"),
                                     action: micToggle.action)
                }
                if isPaused {
                    Button(action: onResume) {
                        HStack(spacing: 7) {
                            GrabiIconView(.reanudar, size: 12, tint: GrabiColor.inkFixed)
                            Text(L("ui.reanudar"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(GrabiColor.inkFixed)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(GrabiColor.ivoryFixed))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("ui.reanudar"))
                } else {
                    PillCircleButton(kind: .pausa, action: onPause, size: 30)
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
        .accessibilityLabel(String(format: isPaused ? L("ui.a11y.pillPausa") : L("ui.a11y.grabando"), elapsed))
    }
}

/// Manija de arrastre (6 puntos), visible en la pastilla.
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


/// Toggle de fuente en la pastilla (cámara/mic en vivo): encendido = ícono
/// marfil con borde; apagado = ícono atenuado con barra diagonal ámbar
/// (semántica del semáforo: ámbar = en pausa, no error).
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
