// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Record",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit with system-audio capture requires macOS 13+
    ],
    dependencies: [
        // The ONLY external dependency, deliberately: Sparkle is the de facto
        // open-source standard for macOS app updates. Everything else is
        // Apple frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: [
        // ---- Layers ------------------------------------------------------
        // Domain: entities, value objects and ports. Pure Swift — no
        // AVFoundation, no AppKit, no SwiftUI. Runs (and tests) anywhere.
        .target(name: "GrabiDomain"),
        // Use cases: the application's behavior, written against the ports.
        .target(name: "GrabiUseCases", dependencies: ["GrabiDomain"]),
        .testTarget(name: "GrabiDomainTests", dependencies: ["GrabiDomain"]),
        .testTarget(name: "GrabiUseCasesTests", dependencies: ["GrabiUseCases", "GrabiDomain"]),

        // Infrastructure: the adapters that implement the ports with
        // ScreenCaptureKit, AVFoundation and the file system.
        .target(
            name: "RecordEngine",
            dependencies: ["GrabiDomain"],
            resources: [.process("Resources")]
        ),
        // Grabi design system: tokens, icons, mascot, and SwiftUI components.
        .target(
            name: "RecordUI",
            dependencies: ["GrabiDomain", "RecordEngine"],
            resources: [.process("Resources")]
        ),
        // The app.
        .executableTarget(
            name: "RecordApp",
            dependencies: [
                "GrabiDomain", "GrabiUseCases", "RecordEngine", "RecordUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
            dependencies: ["GrabiDomain", "RecordEngine"]
        ),
    ]
)
