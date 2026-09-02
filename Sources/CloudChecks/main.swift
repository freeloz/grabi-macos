import Foundation
import GrabiCloud
import GrabiDomain
import GrabiUseCases

// Cloud integration checks: the REAL share flow (sign in → web-safe export →
// upload → link) against staging, without the app UI. Same spirit as
// EngineChecks: verify the seam where mocks can lie.
//
//   swift run CloudChecks <video> [staging|production]
//
// Usa la sesión que la app ya guardó en el llavero: desde que Supabase exige
// captcha (28 ago 2026), entrar con correo y contraseña desde fuera del
// navegador está bloqueado. Primero se inicia sesión en la app (o en
// "Grabi Staging"), y esta herramienta reutiliza esa sesión.

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: CloudChecks <video-path> [staging|production]")
    print("  (inicia sesión antes en la app del ambiente que vayas a probar)")
    exit(2)
}
let videoURL = URL(fileURLWithPath: args[1])
let environment: CloudEnvironment = (args.count > 2 && args[2] == "production") ? .production : .staging

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
        let cloud = GrabiCloudAdapter(environment: environment,
                                      sessionSlot: environment.isStaging ? "session.staging" : "session")
        print("→ sesión del llavero…")
        guard let account = await cloud.account() else {
            print("✗ no hay sesión guardada para \(environment.isStaging ? "staging" : "producción").")
            print("  Inicia sesión en la app correspondiente y vuelve a correr esto.")
            exit(1)
        }
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
