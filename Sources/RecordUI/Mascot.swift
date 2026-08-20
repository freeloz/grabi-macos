import SwiftUI

/// La mascota Grabi: el punto rojo de grabar, con cara (Fase 1 §02).
/// Poses portadas 1:1 de los SVG del manual (viewBox 0 0 96 96).
///
/// Reglas del manual aplicadas aquí:
/// - Cuerpo siempre círculo perfecto; color según contexto (marca = rec;
///   semáforo del producto = exito/rec/advertencia).
/// - Ondas de pulso SOLO cuando realmente se está grabando.
/// - Con "reducir movimiento", el pulso queda estático (opacidad 0,55).
public enum MascotPose {
    case neutral        // reposo
    case grabando       // concentrado + ondas
    case exito          // sonrisa grande
    case error          // ojos X — siempre junto a una solución
    case saludando      // onboarding y estados vacíos
    case preocupado     // permisos ("o" en la boca)
    case pausado        // ojos = icono de pausa (semáforo)
    case listo          // sonrisa suave (semáforo verde)
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

    private var hasWaves: Bool { pose == .grabando }

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

            // Ondas de pulso (solo grabando). Animadas por opacidad; con
            // reduce-motion quedan fijas en 0,55.
            if hasWaves {
                let outerOpacity = reduceMotion ? 0.55 : (pulsing ? 0.08 : 0.55)
                context.stroke(circle(48, 50, 42), with: .color(bodyColor.opacity(outerOpacity)), style: strokeStyle(2.5))
                context.stroke(circle(48, 50, 36), with: .color(bodyColor.opacity(0.35)), style: strokeStyle(2.5))
            }

            // Brazo (solo saludando; el manual permite brazos en ≥64 px)
            if pose == .saludando, size >= 64 {
                var arm = Path()
                arm.move(to: P(73, 52))
                arm.addQuadCurve(to: P(84, 32), control: P(86, 47))
                context.stroke(arm, with: bodyShading, style: strokeStyle(7))
                context.fill(circle(84, 30, 5.5), with: bodyShading)
            }

            // Cuerpo
            context.fill(circle(48, 50, 30), with: bodyShading)

            // Ojos
            switch pose {
            case .neutral, .saludando, .preocupado, .listo:
                context.fill(circle(40, 45, 4.2), with: face)
                if pose == .saludando {
                    var wink = Path()
                    wink.move(to: P(52, 45))
                    wink.addQuadCurve(to: P(60, 45), control: P(56, 41))
                    context.stroke(wink, with: face, style: strokeStyle(3.2))
                } else {
                    context.fill(circle(56, 45, 4.2), with: face)
                }
            case .grabando:
                context.fill(rrect(35.5, 43, 9, 4.5, 2.25), with: face)
                context.fill(rrect(51.5, 43, 9, 4.5, 2.25), with: face)
            case .exito:
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
            case .pausado:
                // Los ojos SON el icono de pausa.
                context.fill(rrect(38, 40, 5.5, 13, 2.75), with: face)
                context.fill(rrect(52.5, 40, 5.5, 13, 2.75), with: face)
            }

            // Boca
            switch pose {
            case .neutral:
                context.fill(rrect(41, 58, 14, 5.5, 2.75), with: face)
            case .grabando:
                context.fill(rrect(42, 58, 12, 5, 2.5), with: face)
            case .exito, .saludando:
                var mouth = Path()
                mouth.move(to: P(39, 57))
                mouth.addQuadCurve(to: P(57, 57), control: P(48, 68))
                context.stroke(mouth, with: face, style: strokeStyle(4))
            case .error:
                context.fill(circle(48, 62, 3.8), with: face)
            case .preocupado:
                context.fill(Path(ellipseIn: CGRect(x: (48 - 4.5) * s, y: (61 - 3.5) * s, width: 9 * s, height: 7 * s)), with: face)
            case .pausado:
                context.fill(rrect(42, 60, 12, 5, 2.5), with: face)
            case .listo:
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

/// El punto del semáforo (Fase 1: verde listo · rojo grabando · ámbar pausado).
/// El punto rojo pulsa en sincronía con la mascota (1,6 s).
public struct SemaforoDot: View {
    public enum Estado { case listo, grabando, pausado, apagado }

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
            case .listo:
                Circle().fill(GrabiColor.exito)
            case .grabando:
                Circle().fill(GrabiColor.rec)
                    .opacity(reduceMotion ? 0.55 : (pulsing ? 0.08 : 0.55))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: GrabiDuration.pulse / 2).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
            case .pausado:
                // Pausado es cuadradito redondeado, no círculo (Fase 2 §07).
                RoundedRectangle(cornerRadius: size * 0.23).fill(GrabiColor.advertencia)
            case .apagado:
                Circle().fill(GrabiColor.switchOff)
            }
        }
        .frame(width: size, height: size)
    }
}
