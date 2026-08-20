import SwiftUI
import RecordEngine

/// Estado de una fila de fuente (Fase 2 §04 y Fase 3 §04):
/// activa · inactiva · sin permiso (acción) · no disponible · celebración.
public enum SourceRowStatus: Equatable {
    case normal
    /// Falta permiso: fondo tint-advertencia, switch bloqueado, enlace de acción.
    case sinPermiso
    /// No disponible físicamente: 45 % opacidad, switch bloqueado, texto honesto.
    case noDisponible
    /// Permiso recién concedido: celebra 2 s en tint-exito.
    case celebracion
}

/// Fila de fuente: ícono + título + subtítulo + switch nativo teñido con
/// color.exito (encendido = verde, coherente con el semáforo). Toda la fila
/// es clicable, no solo el switch.
public struct SourceRow: View {
    let icon: GrabiIcon
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    @Binding var isOn: Bool
    /// Nivel de audio 0–1 para el medidor sutil (solo mic/audio del sistema).
    let level: Double?
    let onPermissionTap: (() -> Void)?

    public init(icon: GrabiIcon,
                title: String,
                subtitle: String,
                status: SourceRowStatus = .normal,
                isOn: Binding<Bool>,
                level: Double? = nil,
                onPermissionTap: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self._isOn = isOn
        self.level = level
        self.onPermissionTap = onPermissionTap
    }

    private var blocked: Bool { status == .sinPermiso || status == .noDisponible }

    public var body: some View {
        HStack(spacing: 11) {
            GrabiIconView(icon, size: 18, tint: iconTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrabiColor.text)
                subtitleView
                if let level, isOn, status == .normal {
                    LevelMeter(level: level)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: GrabiSpace.s2)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(GrabiColor.exito)
                .disabled(blocked)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(rowBackground)
        .opacity(status == .noDisponible ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // Toda la fila es clicable. Sin permiso → abre el flujo de permiso.
            if status == .sinPermiso {
                onPermissionTap?()
            } else if !blocked {
                isOn.toggle()
            }
        }
        .animation(GrabiAnimation.standard(0.3), value: status)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch status {
        case .sinPermiso:
            HStack(spacing: 3) {
                Text("Falta permiso ·")
                Text("Dar permiso…").underline()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(GrabiColor.advertencia)
        case .celebracion:
            Text(subtitle)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GrabiColor.exito)
        default:
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(GrabiColor.textSecondary)
        }
    }

    private var iconTint: Color {
        status == .sinPermiso ? GrabiColor.advertencia : GrabiColor.text
    }

    private var rowBackground: Color {
        switch status {
        case .sinPermiso: return GrabiColor.advertenciaBg
        case .celebracion: return GrabiColor.exitoBg
        default: return .clear
        }
    }
}

/// Medidor de nivel sutil (decisión de producto 2026-08: barrita discreta en
/// las filas de audio, con color.exito; no existe en design/ v1).
public struct LevelMeter: View {
    let level: Double // 0–1

    public init(level: Double) {
        self.level = min(max(level, 0), 1)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(GrabiColor.track)
                Capsule()
                    .fill(GrabiColor.exito)
                    .frame(width: max(3, geo.size.width * level))
                    .animation(GrabiAnimation.standard(0.1), value: level)
            }
        }
        .frame(width: 120, height: 3)
        .accessibilityHidden(true)
    }
}

/// Contenedor de filas de fuente: tarjeta con divisores (Fase 3 §01).
public struct SourceList<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(GrabiColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GrabiColor.border, lineWidth: 1))
    }
}

/// Divisor entre filas.
public struct RowDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(GrabiColor.divider).frame(height: 1)
    }
}
