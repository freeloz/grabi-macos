import SwiftUI
import GrabiDomain

/// Grabi custom icons (Phase 1 §06): 24 px grid, stroke 2, round caps,
/// they inherit the context color (`foregroundStyle`). The red fill only
/// exists in `record` (manual rule).
public enum GrabiIcon: String, CaseIterable, Sendable {
    case record, pause, stop, resume
    case screen, window, region
    case microphone, systemAudio
    case camCircle, camSquare, camRect
    case folder
    case settings
}

public struct GrabiIconView: View {
    let icon: GrabiIcon
    let size: CGFloat
    let tint: Color

    public init(_ icon: GrabiIcon, size: CGFloat = 24, tint: Color = GrabiColor.text) {
        self.icon = icon
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24 // scale from the 24 grid
            let stroke = StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round)
            let color = GraphicsContext.Shading.color(tint)

            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
                var p = Path(); p.move(to: P(x1, y1)); p.addLine(to: P(x2, y2)); return p
            }

            switch icon {
            case .record:
                context.stroke(circle(12, 12, 9), with: color, style: stroke)
                context.fill(circle(12, 12, 4), with: .color(GrabiColor.rec))
            case .pause:
                context.stroke(line(9, 6, 9, 18), with: color, style: stroke)
                context.stroke(line(15, 6, 15, 18), with: color, style: stroke)
            case .stop:
                context.stroke(rect(6, 6, 12, 12, 2.5), with: color, style: stroke)
            case .resume:
                var p = Path()
                p.move(to: P(8, 5.5)); p.addLine(to: P(19, 12)); p.addLine(to: P(8, 18.5)); p.closeSubpath()
                context.fill(p, with: color)
            case .screen:
                context.stroke(rect(3, 5, 18, 12, 2), with: color, style: stroke)
                context.stroke(line(9, 20, 15, 20), with: color, style: stroke)
            case .window:
                context.stroke(rect(4, 5, 16, 14, 2), with: color, style: stroke)
                context.stroke(line(4, 9.5, 20, 9.5), with: color, style: stroke)
                context.fill(circle(7, 7.3, 0.8), with: color)
            case .region:
                for corner in 0..<4 {
                    var p = Path()
                    switch corner {
                    case 0: p.move(to: P(4, 9)); p.addLine(to: P(4, 6)); p.addQuadCurve(to: P(6, 4), control: P(4, 4)); p.addLine(to: P(9, 4))
                    case 1: p.move(to: P(15, 4)); p.addLine(to: P(18, 4)); p.addQuadCurve(to: P(20, 6), control: P(20, 4)); p.addLine(to: P(20, 9))
                    case 2: p.move(to: P(20, 15)); p.addLine(to: P(20, 18)); p.addQuadCurve(to: P(18, 20), control: P(20, 20)); p.addLine(to: P(15, 20))
                    default: p.move(to: P(9, 20)); p.addLine(to: P(6, 20)); p.addQuadCurve(to: P(4, 18), control: P(4, 20)); p.addLine(to: P(4, 15))
                    }
                    context.stroke(p, with: color, style: stroke)
                }
            case .microphone:
                context.stroke(rect(9, 3, 6, 11, 3), with: color, style: stroke)
                var arc = Path()
                arc.move(to: P(5, 11))
                arc.addArc(center: P(12, 11), radius: 7 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                context.stroke(arc, with: color, style: stroke)
                context.stroke(line(12, 18, 12, 21), with: color, style: stroke)
            case .systemAudio:
                var p = Path()
                p.move(to: P(4, 9)); p.addLine(to: P(7, 9)); p.addLine(to: P(11, 5))
                p.addLine(to: P(11, 19)); p.addLine(to: P(7, 15)); p.addLine(to: P(4, 15)); p.closeSubpath()
                context.stroke(p, with: color, style: stroke)
                var w1 = Path()
                w1.move(to: P(15, 9))
                w1.addQuadCurve(to: P(15, 15), control: P(18.2, 12))
                context.stroke(w1, with: color, style: stroke)
                var w2 = Path()
                w2.move(to: P(18, 6.5))
                w2.addQuadCurve(to: P(18, 17.5), control: P(23.5, 12))
                context.stroke(w2, with: color, style: stroke)
            case .camCircle:
                context.stroke(circle(12, 12, 8), with: color, style: stroke)
                context.stroke(circle(12, 10.5, 2.5), with: color, style: stroke)
                var p = Path()
                p.move(to: P(7.5, 18))
                p.addQuadCurve(to: P(16.5, 18), control: P(12, 13.5))
                context.stroke(p, with: color, style: stroke)
            case .camSquare:
                context.stroke(rect(4, 4, 16, 16, 3), with: color, style: stroke)
                context.stroke(circle(12, 10.5, 2.5), with: color, style: stroke)
                var p = Path()
                p.move(to: P(7.5, 18.5))
                p.addQuadCurve(to: P(16.5, 18.5), control: P(12, 14))
                context.stroke(p, with: color, style: stroke)
            case .camRect:
                context.stroke(rect(3, 6, 18, 12, 3), with: color, style: stroke)
                context.stroke(circle(12, 10.5, 2), with: color, style: stroke)
                var p = Path()
                p.move(to: P(8.5, 16))
                p.addQuadCurve(to: P(15.5, 16), control: P(12, 12.5))
                context.stroke(p, with: color, style: stroke)
            case .settings:
                context.stroke(circle(12, 12, 3), with: color, style: stroke)
                for (x1, y1, x2, y2) in [(12.0, 3.0, 12.0, 5.5), (12.0, 18.5, 12.0, 21.0), (3.0, 12.0, 5.5, 12.0), (18.5, 12.0, 21.0, 12.0), (5.6, 5.6, 7.4, 7.4), (16.6, 16.6, 18.4, 18.4), (18.4, 5.6, 16.6, 7.4), (7.4, 16.6, 5.6, 18.4)] {
                    context.stroke(line(x1, y1, x2, y2), with: color, style: stroke)
                }
            case .folder:
                var p = Path()
                p.move(to: P(3, 7))
                p.addQuadCurve(to: P(5, 5), control: P(3, 5))
                p.addLine(to: P(9, 5)); p.addLine(to: P(11, 7)); p.addLine(to: P(19, 7))
                p.addQuadCurve(to: P(21, 9), control: P(21, 7))
                p.addLine(to: P(21, 18))
                p.addQuadCurve(to: P(19, 20), control: P(21, 20))
                p.addLine(to: P(5, 20))
                p.addQuadCurve(to: P(3, 18), control: P(3, 20))
                p.closeSubpath()
                context.stroke(p, with: color, style: stroke)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Camera shape icon based on the engine's `CameraShape`.
import RecordEngine

public extension GrabiIcon {
    static func forShape(_ shape: CameraShape) -> GrabiIcon {
        switch shape {
        case .circle: return .camCircle
        case .square: return .camSquare
        case .rectangle: return .camRect
        }
    }

    static func forSource(_ source: RecordingSource) -> GrabiIcon {
        switch source {
        case .screen: return .screen
        case .camera: return .camCircle
        case .microphone: return .microphone
        case .systemAudio: return .systemAudio
        }
    }
}
