import SwiftUI

// MARK: - Segmented control (Fase 2 §05)
// Track con thumb blanco que se desliza 200 ms easing.standard. Máx. 3 opciones.

public struct GrabiSegmentItem<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String?
    public let icon: GrabiIcon?

    public var id: Value { value }

    public init(_ value: Value, label: String? = nil, icon: GrabiIcon? = nil) {
        self.value = value
        self.label = label
        self.icon = icon
    }
}

public struct GrabiSegmented<Value: Hashable>: View {
    let items: [GrabiSegmentItem<Value>]
    @Binding var selection: Value
    @Namespace private var thumb

    public init(items: [GrabiSegmentItem<Value>], selection: Binding<Value>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(GrabiAnimation.standard()) { selection = item.value }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = item.icon {
                            GrabiIconView(icon, size: 14, tint: selected ? GrabiColor.text : GrabiColor.textSecondary)
                        }
                        if let label = item.label {
                            Text(label)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? GrabiColor.text : GrabiColor.textSecondary)
                        }
                    }
                    .padding(.vertical, item.label == nil ? 5 : 6)
                    .padding(.horizontal, item.label == nil ? 12 : 0)
                    .frame(maxWidth: item.label == nil ? nil : .infinity)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(GrabiColor.segmentThumb)
                                .grabiShadow(.e1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label ?? String(describing: item.value))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2.5)
        .background(GrabiColor.track)
        .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.sm))
        .grabiFocusRing(RoundedRectangle(cornerRadius: GrabiRadius.sm))
    }
}

// MARK: - Badges (Fase 2 §07)

/// Badge ● REC — nunca desaparece mientras se graba (promesa de honestidad).
public struct RecBadge: View {
    let elapsed: String

    public init(elapsed: String) {
        self.elapsed = elapsed
    }

    public var body: some View {
        HStack(spacing: 7) {
            SemaforoDot(.grabando, size: 9)
            Text("REC")
                .font(.system(size: 12, weight: .bold))
                .kerning(0.96)
                .foregroundStyle(GrabiColor.ivoryFixed)
            Text(elapsed)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(GrabiColor.ivoryFixedDim)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(Capsule().fill(GrabiColor.inkFixed))
        .accessibilityLabel(String(format: L("ui.a11y.recording"), elapsed))
    }
}

/// Badge de estado con tint (Listo / Pausado / duración de clip).
public struct StatusBadge: View {
    public enum Kind { case listo, pausado, duracion }
    let kind: Kind
    let text: String

    public init(_ kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 7) {
            switch kind {
            case .listo: Circle().fill(GrabiColor.exito).frame(width: 9, height: 9)
            case .pausado: RoundedRectangle(cornerRadius: 2.5).fill(GrabiColor.advertencia).frame(width: 9, height: 9)
            case .duracion: EmptyView()
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint))
    }

    private var color: Color {
        switch kind {
        case .listo: return GrabiColor.exito
        case .pausado: return GrabiColor.advertencia
        case .duracion: return GrabiColor.error
        }
    }

    private var tint: Color {
        switch kind {
        case .listo: return GrabiColor.tintExito
        case .pausado: return GrabiColor.tintAdvertencia
        case .duracion: return GrabiColor.tintRec
        }
    }
}

// MARK: - Toasts (Fase 2 §06)
// Éxito: miniatura + acción, se va sola a los 6 s. Error: mascota + solución,
// no se va sola. La mascota solo aparece en errores y celebraciones.

public struct GrabiToast: View {
    public enum Kind {
        case exito(thumbnail: NSImage?, meta: String, actionLabel: String, action: () -> Void)
        case error(mensaje: String, actionLabel: String, action: () -> Void)
    }

    let title: String
    let kind: Kind

    public init(title: String, kind: Kind) {
        self.title = title
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: 13) {
            switch kind {
            case .exito(let thumbnail, let meta, let actionLabel, let action):
                thumbnailView(thumbnail)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GrabiFont.bodySemibold)
                        .foregroundStyle(GrabiColor.text)
                    Text(meta)
                        .font(.system(size: 12.5))
                        .foregroundStyle(GrabiColor.textSecondary)
                }
                Spacer(minLength: GrabiSpace.s2)
                smallButton(actionLabel, primary: true, action: action)
            case .error(let mensaje, let actionLabel, let action):
                MascotView(pose: .error, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GrabiFont.bodySemibold)
                        .foregroundStyle(GrabiColor.error)
                    Text(mensaje)
                        .font(.system(size: 12.5))
                        .foregroundStyle(GrabiColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: GrabiSpace.s2)
                smallButton(actionLabel, primary: false, action: action)
            }
        }
        .padding(.horizontal, GrabiSpace.s4)
        .padding(.vertical, 14)
        .background(GrabiColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GrabiColor.border, lineWidth: 1))
        .grabiShadow(.e2)
    }

    private func thumbnailView(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                GrabiColor.track
            }
        }
        .frame(width: 56, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func smallButton(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary ? GrabiColor.onBrand : GrabiColor.text)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(primary ? GrabiColor.brandStrong : GrabiColor.surface)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(primary ? .clear : GrabiColor.borderStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modal (Fase 2 §06) — solo para decisiones destructivas.

public struct GrabiModal: View {
    let title: String
    let message: String
    let safeLabel: String
    let destructiveLabel: String
    let onSafe: () -> Void
    let onDestructive: () -> Void

    public init(title: String, message: String,
                safeLabel: String, destructiveLabel: String,
                onSafe: @escaping () -> Void, onDestructive: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.safeLabel = safeLabel
        self.destructiveLabel = destructiveLabel
        self.onSafe = onSafe
        self.onDestructive = onDestructive
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GrabiSpace.s3) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GrabiColor.text)
            Text(message)
                .font(GrabiFont.body)
                .foregroundStyle(GrabiColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: GrabiSpace.s2 + 2) {
                Spacer()
                // La opción segura siempre a la izquierda y como fantasma; Esc = conservar.
                GrabiButton(safeLabel, kind: .fantasma, action: onSafe)
                    .keyboardShortcut(.cancelAction)
                GrabiButton(destructiveLabel, kind: .destructivo, action: onDestructive)
            }
            .padding(.top, GrabiSpace.s2)
        }
        .padding(26)
        .frame(width: 340)
        .background(GrabiColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: GrabiRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: GrabiRadius.lg).strokeBorder(GrabiColor.border, lineWidth: 1))
        .grabiShadow(.e3)
    }
}

// MARK: - Tooltip (Fase 2 §06): oscuro, aparece a los 500 ms.

private struct GrabiTooltipModifier: ViewModifier {
    let text: String
    @State private var visible = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                task?.cancel()
                if inside {
                    task = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if !Task.isCancelled {
                            await MainActor.run { withAnimation(GrabiAnimation.standard(GrabiDuration.fast)) { visible = true } }
                        }
                    }
                } else {
                    visible = false
                }
            }
            .overlay(alignment: .top) {
                if visible {
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(GrabiColor.ivoryFixed)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(GrabiColor.inkFixed))
                        .grabiShadow(.e1)
                        .fixedSize()
                        .offset(y: -32)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .help(text) // accesibilidad: tooltip del sistema para VoiceOver
    }
}

public extension View {
    func grabiTooltip(_ text: String) -> some View {
        modifier(GrabiTooltipModifier(text: text))
    }
}
