import SwiftUI

/// The Grabi mascot: the red record dot, with a face (Phase 1 §02).
/// Poses ported 1:1 from the manual's SVGs (viewBox 0 0 96 96).
///
/// Manual rules applied here:
/// - Body is always a perfect circle; color depends on context (brand = rec;
///   product traffic light = success/rec/advertencia).
/// - Pulse waves ONLY while actually recording.
/// - With "reduce motion", the pulse stays static (opacity 0.55).
public enum MascotPose {
    case neutral        // at rest
    case recording       // focused + waves
    case success          // big smile
    case error          // X eyes — always paired with a solution
    case waving      // onboarding and empty states
    case worried     // permissions ("o" mouth)
    case paused        // eyes = pause icon (traffic light)
    case ready          // soft smile (green traffic light)
}

public struct MascotView: View {
    let pose: MascotPose
    let size: CGFloat
    let bodyColor: Color
    let faceColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    public init(pose: MascotPose,
                size: CGFloat = 96,
                bodyColor: Color = GrabiColor.rec,
                faceColor: Color = GrabiColor.mascotFace) {
        self.pose = pose
        self.size = size
        self.bodyColor = bodyColor
        self.faceColor = faceColor
    }

    private var hasWaves: Bool { pose == .recording }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 96
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            func strokeStyle(_ width: CGFloat) -> StrokeStyle {
                StrokeStyle(lineWidth: width * s, lineCap: .round)
            }
            let bodyShading = GraphicsContext.Shading.color(bodyColor)
            let face = GraphicsContext.Shading.color(faceColor)

            // Pulse waves (recording only). Animated via opacity; with
            // reduce-motion they stay fixed at 0.55.
            if hasWaves {
                let outerOpacity = reduceMotion ? 0.55 : (pulsing ? 0.08 : 0.55)
                context.stroke(circle(48, 50, 42), with: .color(bodyColor.opacity(outerOpacity)), style: strokeStyle(2.5))
                context.stroke(circle(48, 50, 36), with: .color(bodyColor.opacity(0.35)), style: strokeStyle(2.5))
            }

            // Arm (waving only; the manual allows arms at ≥64 px)
            if pose == .waving, size >= 64 {
                var arm = Path()
                arm.move(to: P(73, 52))
                arm.addQuadCurve(to: P(84, 32), control: P(86, 47))
                context.stroke(arm, with: bodyShading, style: strokeStyle(7))
                context.fill(circle(84, 30, 5.5), with: bodyShading)
            }

            // Body
            context.fill(circle(48, 50, 30), with: bodyShading)

            // Eyes
            switch pose {
            case .neutral, .waving, .worried, .ready:
                context.fill(circle(40, 45, 4.2), with: face)
                if pose == .waving {
                    var wink = Path()
                    wink.move(to: P(52, 45))
                    wink.addQuadCurve(to: P(60, 45), control: P(56, 41))
                    context.stroke(wink, with: face, style: strokeStyle(3.2))
                } else {
                    context.fill(circle(56, 45, 4.2), with: face)
                }
            case .recording:
                context.fill(rrect(35.5, 43, 9, 4.5, 2.25), with: face)
                context.fill(rrect(51.5, 43, 9, 4.5, 2.25), with: face)
            case .success:
                for x: CGFloat in [35, 51] {
                    var eye = Path()
                    eye.move(to: P(x, 45))
                    eye.addQuadCurve(to: P(x + 10, 45), control: P(x + 5, 38))
                    context.stroke(eye, with: face, style: strokeStyle(3.5))
                }
            case .error:
                for x: CGFloat in [36, 52] {
                    var eye = Path()
                    eye.move(to: P(x, 42)); eye.addLine(to: P(x + 8, 49))
                    eye.move(to: P(x + 8, 42)); eye.addLine(to: P(x, 49))
                    context.stroke(eye, with: face, style: strokeStyle(3.2))
                }
            case .paused:
                // The eyes ARE the pause icon.
                context.fill(rrect(38, 40, 5.5, 13, 2.75), with: face)
                context.fill(rrect(52.5, 40, 5.5, 13, 2.75), with: face)
            }

            // Mouth
            switch pose {
            case .neutral:
                context.fill(rrect(41, 58, 14, 5.5, 2.75), with: face)
            case .recording:
                context.fill(rrect(42, 58, 12, 5, 2.5), with: face)
            case .success, .waving:
                var mouth = Path()
                mouth.move(to: P(39, 57))
                mouth.addQuadCurve(to: P(57, 57), control: P(48, 68))
                context.stroke(mouth, with: face, style: strokeStyle(4))
            case .error:
                context.fill(circle(48, 62, 3.8), with: face)
            case .worried:
                context.fill(Path(ellipseIn: CGRect(x: (48 - 4.5) * s, y: (61 - 3.5) * s, width: 9 * s, height: 7 * s)), with: face)
            case .paused:
                context.fill(rrect(42, 60, 12, 5, 2.5), with: face)
            case .ready:
                var mouth = Path()
                mouth.move(to: P(40, 57))
                mouth.addQuadCurve(to: P(56, 57), control: P(48, 65))
                context.stroke(mouth, with: face, style: strokeStyle(3.5))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard hasWaves, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: GrabiDuration.pulse / 2).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// The traffic-light dot (Phase 1: green ready · red recording · amber paused).
/// The red dot pulses in sync with the mascot (1.6 s).
public struct SemaforoDot: View {
    public enum Estado { case ready, recording, paused, apagado }

    let estado: Estado
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    public init(_ estado: Estado, size: CGFloat = 13) {
        self.estado = estado
        self.size = size
    }

    public var body: some View {
        Group {
            switch estado {
            case .ready:
                Circle().fill(GrabiColor.success)
            case .recording:
                Circle().fill(GrabiColor.rec)
                    .opacity(reduceMotion ? 0.55 : (pulsing ? 0.08 : 0.55))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: GrabiDuration.pulse / 2).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
            case .paused:
                // Paused is a small rounded square, not a circle (Phase 2 §07).
                RoundedRectangle(cornerRadius: size * 0.23).fill(GrabiColor.advertencia)
            case .apagado:
                Circle().fill(GrabiColor.switchOff)
            }
        }
        .frame(width: size, height: size)
    }
}
