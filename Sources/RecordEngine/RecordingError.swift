import Foundation

/// Errores del motor, en español y con instrucciones accionables.
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
        case .sinFuentesActivas:
            return "No hay ninguna fuente activada. Activa al menos una (pantalla, cámara, micrófono o audio del sistema) para poder grabar."
        case .permisoPantallaDenegado:
            return "Falta el permiso de Grabación de Pantalla. Ábrelo en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema, activa RecordApp y vuelve a intentarlo (puede que tengas que reabrir la app)."
        case .permisoCamaraDenegado:
            return "Falta el permiso de Cámara. Actívalo en Ajustes del Sistema → Privacidad y seguridad → Cámara, o desactiva la cámara para grabar sin ella."
        case .permisoMicrofonoDenegado:
            return "Falta el permiso de Micrófono. Actívalo en Ajustes del Sistema → Privacidad y seguridad → Micrófono, o desactiva el micrófono para grabar sin él."
        case .camaraNoDisponible:
            return "No se encontró ninguna cámara conectada. Desactiva la cámara para grabar sin ella."
        case .microfonoNoDisponible:
            return "No se encontró ningún micrófono. Desactiva el micrófono para grabar sin él."
        case .pantallaNoEncontrada:
            return "No se encontró la pantalla seleccionada. ¿Se desconectó? Elige otra pantalla e inténtalo de nuevo."
        case .ventanaNoEncontrada:
            return "No se encontró la ventana seleccionada. Puede que se haya cerrado — elige otra ventana."
        case .regionInvalida:
            return "La región seleccionada es demasiado pequeña. Dibuja un recuadro de al menos 16×16 puntos."
        case .capturaInterrumpida(let detalle):
            return "La captura se interrumpió: \(detalle). La grabación se detuvo y se intentó guardar lo capturado hasta ese momento."
        case .escrituraFallida(let detalle):
            return "No se pudo escribir el archivo de grabación: \(detalle)"
        case .nadaGrabado:
            return "La grabación se detuvo antes de recibir ningún dato, así que no se guardó ningún archivo."
        case .estadoInvalido(let detalle):
            return "Operación no válida en el estado actual: \(detalle)"
        }
    }
}
