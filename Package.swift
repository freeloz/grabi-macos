// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Record",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit with system-audio capture requires macOS 13+
    ],
    targets: [
        // Recording engine: no UI, Apple frameworks only.
        .target(
            name: "RecordEngine",
            resources: [.process("Resources")]
        ),
        // Grabi design system: tokens, icons, mascot, and SwiftUI components.
        .target(
            name: "RecordUI",
            dependencies: ["RecordEngine"],
            resources: [.process("Resources")]
        ),
        // The app.
        .executableTarget(
            name: "RecordApp",
            dependencies: ["RecordEngine", "RecordUI"],
            resources: [.process("Resources")],
            linkerSettings: [
                // Embeds Info.plist in the binary (__info_plist section)
                // so the permission dialogs also work when running via
                // `swift run`, outside the .app bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ])
            ]
        ),
        // Engine integration checks (CLT ships without XCTest):
        // `swift run EngineChecks` — synthetic sources, no TCC permissions.
        .executableTarget(
            name: "EngineChecks",
            dependencies: ["RecordEngine"]
        ),
    ]
)
