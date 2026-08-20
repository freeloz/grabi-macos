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
        // App SwiftUI mínima que consume el motor.
        .executableTarget(
            name: "RecordApp",
            dependencies: ["RecordEngine"]
        ),
    ]
)
