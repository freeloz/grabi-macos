import SwiftUI

/// Botones Grabi (Fase 2 §02): altura 36, radio sm (10), tipografía 14/600,
/// transición 120 ms. Foco = anillo, nunca solo cambio de color.
public enum GrabiButtonKind {
    case primario
    case secundario
    case fantasma
    case destructivo
}

public struct GrabiButton: View {
    let title: String
    let kind: GrabiButtonKind
    let isLoading: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String,
                kind: GrabiButtonKind = .secundario,
                isLoading: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: GrabiSpace.s2) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground(pressed: false))
                }
                Text(title)
                    .font(GrabiFont.bodySemibold)
            }
        }
        .buttonStyle(GrabiButtonCore(kind: kind, hovering: hovering))
        .disabled(isLoading)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 && isEnabled }
        .animation(GrabiAnimation.standard(GrabiDuration.fast), value: hovering)
    }

    private func foreground(pressed: Bool) -> Color {
        switch kind {
        case .primario, .destructivo: return GrabiColor.onBrand
        case .secundario, .fantasma: return GrabiColor.text
        }
    }
}

private struct GrabiButtonCore: ButtonStyle {
    let kind: GrabiButtonKind
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(foreground)
            .frame(height: 36)
            .padding(.horizontal, GrabiSpace.s4)
            .background(background(pressed: pressed))
            .overlay(
                RoundedRectangle(cornerRadius: GrabiRadius.sm)
                    .strokeBorder(borderColor, lineWidth: kind == .secundario ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.sm))
            .scaleEffect(pressed ? 0.97 : 1)
            .grabiFocusRing(RoundedRectangle(cornerRadius: GrabiRadius.sm))
            .animation(GrabiAnimation.standard(GrabiDuration.fast), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: GrabiRadius.sm))
    }

    private var foreground: Color {
        switch kind {
        case .primario, .destructivo: return GrabiColor.onBrand
        case .secundario, .fantasma: return GrabiColor.text
        }
    }

    private var borderColor: Color {
        GrabiColor.borderStrong
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primario:
            return pressed ? GrabiColor.brandActive : (hovering ? GrabiColor.brandHover : GrabiColor.brandStrong)
        case .secundario:
            return pressed ? GrabiColor.ghostActive : (hovering ? GrabiColor.bg : GrabiColor.surface)
        case .fantasma:
            return pressed ? GrabiColor.ghostActive : (hovering ? GrabiColor.ghostHover : .clear)
        case .destructivo:
            return pressed ? GrabiColor.errorActive : (hovering ? GrabiColor.errorHover : GrabiColor.error)
        }
    }
}

/// Botón de solo ícono, 36×36 (fila "Ícono" de la Fase 2).
public struct GrabiIconButton: View {
    let icon: GrabiIcon
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    public init(_ icon: GrabiIcon, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            GrabiIconView(icon, size: 17)
        }
        .buttonStyle(IconButtonCore(hovering: hovering))
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 && isEnabled }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct IconButtonCore: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 36, height: 36)
            .background(configuration.isPressed ? GrabiColor.ghostActive : (hovering ? GrabiColor.bg : GrabiColor.surface))
            .overlay(RoundedRectangle(cornerRadius: GrabiRadius.sm).strokeBorder(GrabiColor.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.sm))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .grabiFocusRing(RoundedRectangle(cornerRadius: GrabiRadius.sm))
            .animation(GrabiAnimation.standard(GrabiDuration.fast), value: configuration.isPressed)
    }
}

// MARK: - Anillo de foco (color.focus: 2 px + offset 2 px)

private struct FocusRingModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .overlay(
                shape
                    .inset(by: -4)
                    .strokeBorder(GrabiColor.focus, lineWidth: focused ? 2 : 0)
            )
    }
}

public extension View {
    /// Anillo de foco Grabi: nunca `outline: none` sin reemplazo (Fase 2 §10).
    func grabiFocusRing<S: InsettableShape>(_ shape: S) -> some View {
        modifier(FocusRingModifier(shape: shape))
    }
}
