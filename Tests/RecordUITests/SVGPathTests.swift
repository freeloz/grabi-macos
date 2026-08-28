import XCTest
import SwiftUI
@testable import RecordUI

/// El logo de Google se traza desde su path SVG oficial. Si el parser se
/// equivoca en un comando, el resultado no falla ruidosamente: sale una
/// mancha. Estas pruebas comparan cada trazo contra su equivalente dibujado
/// a mano, que es la única forma de notar la diferencia sin ojos.
final class SVGPathTests: XCTestCase {

    private let box = CGRect(x: 0, y: 0, width: 48, height: 48)

    private func parse(_ d: String, viewBox: CGFloat = 48) -> Path {
        SVGPath(commands: d, viewBox: viewBox).path(in: box)
    }

    func testMoveAndLinesFormTheExpectedRectangle() {
        let square = parse("M10 10 L30 10 L30 25 L10 25 Z")
        XCTAssertEqual(square.boundingRect.minX, 10, accuracy: 0.01)
        XCTAssertEqual(square.boundingRect.minY, 10, accuracy: 0.01)
        XCTAssertEqual(square.boundingRect.width, 20, accuracy: 0.01)
        XCTAssertEqual(square.boundingRect.height, 15, accuracy: 0.01)
    }

    /// Un moveto con pares de sobra continúa como lineto — es lo que hace
    /// que "M24 46c5.94…" no se dibuje como cuatro puntos sueltos.
    func testExtraPairsAfterMovetoBecomeLines() {
        let implicit = parse("M5 5 20 5 20 20")
        let explicit = parse("M5 5 L20 5 L20 20")
        XCTAssertEqual(implicit.boundingRect, explicit.boundingRect)
    }

    func testRelativeCommandsMatchTheirAbsoluteTwins() {
        let relative = parse("m10 10 h20 v15 h-20 z")
        let absolute = parse("M10 10 H30 V25 H10 Z")
        XCTAssertEqual(relative.boundingRect.minX, absolute.boundingRect.minX, accuracy: 0.01)
        XCTAssertEqual(relative.boundingRect.width, absolute.boundingRect.width, accuracy: 0.01)
        XCTAssertEqual(relative.boundingRect.height, absolute.boundingRect.height, accuracy: 0.01)
    }

    /// Los assets de Google vienen minificados: "24s.25-2.86.69-4.18" pega
    /// números con el signo y con el punto. Si el tokenizador no los separa,
    /// el path se deforma en silencio.
    func testMinifiedNumbersAreSplitOnSignAndDecimalPoint() {
        let packed = parse("M10 10l5-5 .5.5z")
        let spaced = parse("M10 10 l5 -5 l0.5 0.5 z")
        XCTAssertEqual(packed.boundingRect.minX, spaced.boundingRect.minX, accuracy: 0.01)
        XCTAssertEqual(packed.boundingRect.minY, spaced.boundingRect.minY, accuracy: 0.01)
        XCTAssertEqual(packed.boundingRect.maxX, spaced.boundingRect.maxX, accuracy: 0.01)
    }

    func testScalesToTheRequestedBox() {
        let half = SVGPath(commands: "M0 0 L48 0 L48 48 Z", viewBox: 48)
            .path(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        XCTAssertEqual(half.boundingRect.width, 24, accuracy: 0.01)
    }

    /// Cada trazo de la G ocupa su cuadrante y ninguno se sale del viewBox:
    /// la comprobación que delata un comando mal interpretado.
    func testGoogleStrokesStayInsideTheViewBox() {
        for (index, stroke) in GoogleMark.strokesForTesting.enumerated() {
            let rect = parse(stroke).boundingRect
            XCTAssertFalse(rect.isEmpty, "el trazo \(index) salió vacío")
            XCTAssertGreaterThanOrEqual(rect.minX, -0.5, "el trazo \(index) se sale por la izquierda")
            XCTAssertGreaterThanOrEqual(rect.minY, -0.5, "el trazo \(index) se sale por arriba")
            XCTAssertLessThanOrEqual(rect.maxX, 48.5, "el trazo \(index) se sale por la derecha")
            XCTAssertLessThanOrEqual(rect.maxY, 48.5, "el trazo \(index) se sale por abajo")
            // Un trazo de la G nunca es una esquirla: si el parser abandona a
            // media curva, el ancho se desploma.
            XCTAssertGreaterThan(rect.width, 5, "el trazo \(index) quedó demasiado estrecho")
        }
    }

    /// Los cuatro trazos juntos cubren la G completa, casi todo el viewBox.
    func testGoogleMarkFillsItsBox() {
        var union = CGRect.null
        for stroke in GoogleMark.strokesForTesting {
            union = union.union(parse(stroke).boundingRect)
        }
        XCTAssertEqual(union.width, 43.12, accuracy: 1.0)
        XCTAssertEqual(union.height, 44, accuracy: 1.0)
    }
}
