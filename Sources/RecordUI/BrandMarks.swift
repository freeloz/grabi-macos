import SwiftUI

/// Marcas de terceros para los botones de identidad.
///
/// Google y Apple exigen su logotipo exacto en los botones de "continuar
/// con…": una aproximación dibujada a mano incumple sus guías de marca y es
/// motivo de rechazo en la revisión de la App Store. Por eso el logo de
/// Google se traza desde su path SVG oficial en vez de aproximarlo con
/// arcos, y el de Apple usa el símbolo del sistema, que es la forma que
/// Apple autoriza.

// MARK: - Parser de paths SVG

/// Traduce el atributo `d` de un `<path>` a un `Path` de SwiftUI.
///
/// Cubre el subconjunto que usan los logotipos: M/m, L/l, H/h, V/v, C/c,
/// S/s y Z/z. No hay arcos (A) porque ninguna de las marcas los usa; si
/// algún día hace falta uno, este es el sitio donde añadirlo.
public struct SVGPath {
    public let commands: String
    /// Lado del `viewBox` original: el path se escala a la caja pedida.
    public let viewBox: CGFloat

    public init(commands: String, viewBox: CGFloat) {
        self.commands = commands
        self.viewBox = viewBox
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / viewBox
        var current = CGPoint.zero      // punto actual, en unidades del viewBox
        var start = CGPoint.zero        // inicio del subpath, para Z
        var lastControl: CGPoint?       // segundo control de la última C/S, para S
        var op: Character = "M"
        var numbers: [CGFloat] = []

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        // Ejecuta el operador pendiente con los números acumulados. Un mismo
        // operador puede repetirse implícitamente ("c" con 12 números = dos
        // curvas), así que se consume por tandas del tamaño que pida.
        func flush() {
            let relative = op.isLowercase
            let arity: Int
            switch op.lowercased().first! {
            case "m", "l": arity = 2
            case "h", "v": arity = 1
            case "c":      arity = 6
            case "s":      arity = 4
            case "z":      arity = 0
            default:       return
            }
            guard arity > 0 else {
                path.closeSubpath()
                current = start
                lastControl = nil
                return
            }
            var i = 0
            var kind = op.lowercased().first!
            while i + arity <= numbers.count {
                let n = Array(numbers[i ..< i + arity])
                switch kind {
                case "m", "l":
                    let p = relative ? CGPoint(x: current.x + n[0], y: current.y + n[1])
                                     : CGPoint(x: n[0], y: n[1])
                    if kind == "m" {
                        path.move(to: point(p.x, p.y))
                        start = p
                        // Tras un moveto, los pares siguientes son linetos.
                        kind = "l"
                    } else {
                        path.addLine(to: point(p.x, p.y))
                    }
                    current = p
                    lastControl = nil
                case "h":
                    let p = CGPoint(x: relative ? current.x + n[0] : n[0], y: current.y)
                    path.addLine(to: point(p.x, p.y))
                    current = p
                    lastControl = nil
                case "v":
                    let p = CGPoint(x: current.x, y: relative ? current.y + n[0] : n[0])
                    path.addLine(to: point(p.x, p.y))
                    current = p
                    lastControl = nil
                case "c", "s":
                    let c1: CGPoint, c2: CGPoint, end: CGPoint
                    if kind == "c" {
                        c1 = relative ? CGPoint(x: current.x + n[0], y: current.y + n[1])
                                      : CGPoint(x: n[0], y: n[1])
                        c2 = relative ? CGPoint(x: current.x + n[2], y: current.y + n[3])
                                      : CGPoint(x: n[2], y: n[3])
                        end = relative ? CGPoint(x: current.x + n[4], y: current.y + n[5])
                                       : CGPoint(x: n[4], y: n[5])
                    } else {
                        // S reutiliza el reflejo del control anterior.
                        let reflected = lastControl.map {
                            CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                        } ?? current
                        c1 = reflected
                        c2 = relative ? CGPoint(x: current.x + n[0], y: current.y + n[1])
                                      : CGPoint(x: n[0], y: n[1])
                        end = relative ? CGPoint(x: current.x + n[2], y: current.y + n[3])
                                       : CGPoint(x: n[2], y: n[3])
                    }
                    path.addCurve(to: point(end.x, end.y),
                                  control1: point(c1.x, c1.y),
                                  control2: point(c2.x, c2.y))
                    current = end
                    lastControl = c2
                default:
                    break
                }
                i += arity
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var token = ""
        func takeNumber() {
            if !token.isEmpty, let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        for ch in commands {
            if ch.isLetter {
                takeNumber()
                flush()
                op = ch
                if ch == "z" || ch == "Z" { flush() }
            } else if ch == "-" && !token.isEmpty && !token.hasSuffix("e") {
                // "1.5-2.3" son dos números pegados: el signo abre el siguiente.
                takeNumber()
                token = "-"
            } else if ch == "." && token.contains(".") {
                // ".5.7" también van pegados.
                takeNumber()
                token = "."
            } else if ch == "," || ch == " " || ch == "\n" {
                takeNumber()
            } else {
                token.append(ch)
            }
        }
        takeNumber()
        flush()
        return path
    }
}

// MARK: - Google

/// La "G" de Google, con sus cuatro trazos oficiales.
public struct GoogleMark: View {
    let size: CGFloat

    public init(size: CGFloat = 17) { self.size = size }

    // Paths del asset oficial de Google Sign-In (viewBox 48×48).
    private static let strokes: [(String, Color)] = [
        ("M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z",
         Color(red: 0.259, green: 0.522, blue: 0.957)),   // #4285F4
        ("M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z",
         Color(red: 0.204, green: 0.659, blue: 0.325)),   // #34A853
        ("M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z",
         Color(red: 0.984, green: 0.737, blue: 0.020)),   // #FBBC05
        ("M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z",
         Color(red: 0.918, green: 0.263, blue: 0.208)),   // #EA4335
    ]

    /// Solo los paths, para que las pruebas comprueben el trazado sin
    /// tener que renderizar una vista.
    static var strokesForTesting: [String] { strokes.map(\.0) }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            for (commands, color) in Self.strokes {
                context.fill(SVGPath(commands: commands, viewBox: 48).path(in: rect),
                             with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)   // el texto del botón ya dice "Google"
    }
}

// MARK: - Apple

/// El logo de Apple. `applelogo` es el símbolo del sistema: es el único
/// uso del logotipo que Apple autoriza sin licencia y siempre está al día.
public struct AppleMark: View {
    let size: CGFloat

    public init(size: CGFloat = 17) { self.size = size }

    public var body: some View {
        Image(systemName: "applelogo")
            .font(.system(size: size * 0.95))
            .foregroundStyle(GrabiColor.text)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
