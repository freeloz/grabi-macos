import Foundation

/// Errores del motor: accionables y localizados (Localizable.strings del
/// target; las instrucciones de permisos usan las rutas REALES de Ajustes
/// del Sistema en cada idioma).
public enum RecordingError: LocalizedError, Equatable {
    case sinFuentesActivas
    case permisoPantallaDenegado
    case permisoCamaraDenegado
    case permisoMicrofonoDenegado
    case camaraNoDisponible
    case microfonoNoDisponible
    case pantallaNoEncontrada
    case ventanaNoEncontrada
    case regionInvalida
    case capturaInterrumpida(String)
    case escrituraFallida(String)
    case nadaGrabado
    case estadoInvalido(String)

    public var errorDescription: String? {
        switch self {
        case .sinFuentesActivas: return L("err.sinFuentes")
        case .permisoPantallaDenegado: return L("err.permisoPantalla")
        case .permisoCamaraDenegado: return L("err.permisoCamara")
        case .permisoMicrofonoDenegado: return L("err.permisoMicrofono")
        case .camaraNoDisponible: return L("err.camaraNoDisponible")
        case .microfonoNoDisponible: return L("err.microfonoNoDisponible")
        case .pantallaNoEncontrada: return L("err.pantallaNoEncontrada")
        case .ventanaNoEncontrada: return L("err.ventanaNoEncontrada")
        case .regionInvalida: return L("err.regionInvalida")
        case .capturaInterrumpida(let detalle): return String(format: L("err.capturaInterrumpida"), detalle)
        case .escrituraFallida(let detalle): return String(format: L("err.escrituraFallida"), detalle)
        case .nadaGrabado: return L("err.nadaGrabado")
        case .estadoInvalido(let detalle): return String(format: L("err.estadoInvalido"), detalle)
        }
    }
}
