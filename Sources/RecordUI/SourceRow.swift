import SwiftUI
import RecordEngine
import GrabiDomain

/// State of a source row (Phase 2 §04 and Phase 3 §04):
/// active · inactive · no permission (action) · unavailable · celebration.
public enum SourceRowStatus: Equatable {
    case normal
    /// Missing permission: tint-advertencia background, locked switch, action link.
    case sinPermiso
    /// Physically unavailable: 45% opacity, locked switch, honest copy.
    case noDisponible
    /// Permission just granted: celebrates for 2 s in tint-success.
    case celebracion
}

/// Source row: icon + title + subtitle + native switch tinted with
/// color.success (on = green, consistent with the traffic light). The whole
/// row is clickable, not just the switch.
public struct SourceRow: View {
    let icon: GrabiIcon
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    @Binding var isOn: Bool
    /// Audio level 0–1 for the subtle meter (mic/system audio only).
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
                .tint(GrabiColor.success)
                .disabled(blocked)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(rowBackground)
        .opacity(status == .noDisponible ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // The whole row is clickable. No permission → open permission flow.
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
                Text(L("ui.permissionMissing"))
                Text(L("ui.grantPermission")).underline()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(GrabiColor.advertencia)
        case .celebracion:
            Text(subtitle)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GrabiColor.success)
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

/// Subtle level meter (product decision 2026-08: discreet little bar on
/// the audio rows, using color.success; does not exist in design/ v1).
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
                    .fill(GrabiColor.success)
                    .frame(width: max(3, geo.size.width * level))
                    .animation(GrabiAnimation.standard(0.1), value: level)
            }
        }
        .frame(width: 120, height: 3)
        .accessibilityHidden(true)
    }
}

/// Container for source rows: card with dividers (Phase 3 §01).
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

/// Divider between rows.
public struct RowDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(GrabiColor.divider).frame(height: 1)
    }
}
