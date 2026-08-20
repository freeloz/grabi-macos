// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Record",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit con captura de audio de sistema requiere macOS 13+
    ],
    targets: [
        // Motor de grabación: sin UI, solo frameworks de Apple.
        .target(
            name: "RecordEngine"
        ),
        // Sistema de diseño Grabi: tokens, íconos, mascota y componentes SwiftUI.
        .target(
            name: "RecordUI",
            dependencies: ["RecordEngine"]
        ),
        // La app.
        .executableTarget(
            name: "RecordApp",
            dependencies: ["RecordEngine", "RecordUI"],
            linkerSettings: [
                // Incrusta el Info.plist en el binario (sección __info_plist)
                // para que los diálogos de permisos funcionen también al
                // ejecutar con `swift run`, fuera del bundle .app.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ])
            ]
        ),
    ]
)
