import Foundation
import GrabiCloud
import GrabiDomain
import GrabiUseCases

// Cloud integration checks: the REAL share flow (sign in → web-safe export →
// upload → link) against staging, without the app UI. Same spirit as
// EngineChecks: verify the seam where mocks can lie.
//
//   swift run CloudChecks <video> <email> <password> [staging|production]

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: CloudChecks <video-path> <email> <password> [staging|production]")
    exit(2)
}
let videoURL = URL(fileURLWithPath: args[1])
let email = args[2]
let password = args[3]
let environment: CloudEnvironment = (args.count > 4 && args[4] == "production") ? .production : .staging

guard FileManager.default.fileExists(atPath: videoURL.path) else {
    print("✗ no existe el video: \(videoURL.path)")
    exit(2)
}

let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
let recording = Recording(
    id: videoURL,
    name: videoURL.deletingPathExtension().lastPathComponent,
    date: (attributes[.creationDate] as? Date) ?? Date(),
    sizeBytes: (attributes[.size] as? Int64) ?? 0
)

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        let cloud = GrabiCloudAdapter(environment: environment)
        print("→ signIn \(email)…")
        let account = try await cloud.signIn(email: email, password: password)
        print("✓ sesión: \(account.email) [\(account.plan)]")

        let share = ShareToCloudUseCase(cloud: cloud)
        print("→ share \(recording.name) (\(recording.sizeBytes) bytes)…")
        let upload = try await share(recording) { stage in
            switch stage {
            case .exporting(let p): print("  exporting \(Int(p * 100))%")
            case .uploading(let p): print("  uploading \(Int(p * 100))%")
            case .finishing: print("  finishing…")
            }
        }
        print("✓ LINK: \(upload.watchURL.absoluteString)")
        if let expires = upload.expiresAt { print("  caduca: \(expires)") }
        exit(0)
    } catch {
        print("✗ \(error)")
        exit(1)
    }
}
semaphore.wait()
