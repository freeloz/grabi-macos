import Foundation
import GrabiDomain

/// The CloudPort adapter: sessions in the Keychain (with silent refresh),
/// export via WebSafeExporter, upload via CloudAPI. An actor because the
/// session is mutable state shared across the app.
public actor GrabiCloudAdapter: CloudPort {
    private let api: CloudAPI
    private let store: CloudSessionStore
    private let exporter: WebSafeExporter
    private var tokens: CloudTokens?

    /// ≤95MB goes in one PUT (Workers body limit ~100MB); above, 50MB parts.
    private static let singleUploadMax: Int64 = 95 * 1024 * 1024
    private static let partSize = 50 * 1024 * 1024

    public init(environment: CloudEnvironment = .current) {
        self.init(api: CloudAPI(env: environment))
    }

    /// Para herramientas sin bundle propio (CloudChecks): elegir el slot del
    /// llavero explícitamente en vez de deducirlo del bundle ID.
    public init(environment: CloudEnvironment, sessionSlot: String) {
        self.init(api: CloudAPI(env: environment), store: CloudSessionStore(account: sessionSlot))
    }

    init(api: CloudAPI, store: CloudSessionStore = CloudSessionStore(),
         exporter: WebSafeExporter = WebSafeExporter()) {
        self.api = api
        self.store = store
        self.exporter = exporter
        self.tokens = store.load()
    }

    // ---- CloudPort -------------------------------------------------------

    public func account() async -> CloudAccount? {
        guard let tokens = try? await validTokens() else { return nil }
        let plan = (try? await api.me(accessToken: tokens.accessToken).plan) ?? "free"
        return CloudAccount(email: tokens.email, plan: plan)
    }

    public func signIn(email: String, password: String) async throws -> CloudAccount {
        let fresh = try await api.signIn(email: email, password: password)
        tokens = fresh
        store.save(fresh)
        let plan = (try? await api.me(accessToken: fresh.accessToken).plan) ?? "free"
        return CloudAccount(email: fresh.email, plan: plan)
    }

    public func signUp(email: String, password: String, locale: String) async throws -> Bool {
        guard let fresh = try await api.signUp(email: email, password: password, locale: locale) else {
            return false // cuenta creada; falta confirmar el correo
        }
        tokens = fresh
        store.save(fresh)
        return true
    }

    public func signOut() async {
        tokens = nil
        store.clear()
    }

    /// La vuelta del navegador: grabi://auth-callback#access_token=…
    /// (grabi-staging:// en la app de pruebas, para no cruzar ambientes).
    public static var oauthRedirect: String { "\(CloudEnvironment.urlScheme)://auth-callback" }

    /// Los proveedores que el servidor tiene activos hoy. Si la red falla nos
    /// quedamos con Google, que es el que siempre ha estado configurado:
    /// mejor un botón de menos que uno que no funciona.
    public func identityProviders() async -> [CloudIdentityProvider] {
        guard let names = try? await api.availableProviders() else { return [.google] }
        let providers = names.compactMap(CloudIdentityProvider.init(rawValue:))
        return providers.isEmpty ? [.google] : providers
    }

    /// Google y Apple entran por la web, igual que el correo: la página
    /// arranca el proveedor y devuelve la sesión por el esquema de la app.
    public nonisolated func oauthAuthorizeURL(provider: CloudIdentityProvider) -> URL {
        api.webLoginURL(redirect: Self.oauthRedirect, provider: provider.rawValue)
    }

    /// Entrar con correo: se hace en la web, no en la app. Ahí vive el
    /// widget de Turnstile que Supabase exige desde el 28 ago, y la web
    /// devuelve la sesión a la app por el esquema grabi://.
    public nonisolated func emailSignInURL() -> URL {
        api.webLoginURL(redirect: Self.oauthRedirect)
    }

    public func adoptSession(accessToken: String, refreshToken: String,
                             expiresIn: Double) async throws -> CloudAccount {
        let handed = CloudTokens(accessToken: accessToken, refreshToken: refreshToken,
                                 expiresAt: Date().addingTimeInterval(expiresIn),
                                 email: "")
        let fresh: CloudTokens
        if let email = try? await api.userEmail(accessToken: accessToken) {
            fresh = CloudTokens(accessToken: accessToken, refreshToken: refreshToken,
                                expiresAt: handed.expiresAt, email: email)
        } else {
            // El access token puede llegar caducado (la web entrega la sesión
            // que tenía guardada). El refresh token sigue valiendo: se canjea
            // antes de rendirse.
            let renewed = try await api.refresh(handed)
            let email = renewed.email.isEmpty
                ? try await api.userEmail(accessToken: renewed.accessToken)
                : renewed.email
            fresh = CloudTokens(accessToken: renewed.accessToken, refreshToken: renewed.refreshToken,
                                expiresAt: renewed.expiresAt, email: email)
        }
        tokens = fresh
        store.save(fresh)
        let plan = (try? await api.me(accessToken: fresh.accessToken).plan) ?? "free"
        return CloudAccount(email: fresh.email, plan: plan)
    }

    public func share(_ recording: Recording, title: String,
               onStage: @escaping @Sendable (CloudShareStage) -> Void) async throws -> CloudUpload {
        let tokens = try await validTokens()

        onStage(.exporting(0))
        let exported = try await exporter.export(recording.id) { onStage(.exporting($0)) }
        defer { try? FileManager.default.removeItem(at: exported.fileURL) }

        let created = try await api.createUpload(
            title: title, durationS: exported.durationS,
            sizeBytes: exported.sizeBytes, accessToken: tokens.accessToken
        )

        onStage(.uploading(0))
        if created.mode == "single" {
            try await api.uploadFile(videoID: created.video_id, fileURL: exported.fileURL,
                                     accessToken: tokens.accessToken)
            onStage(.uploading(1))
        } else {
            try await uploadInParts(created, fileURL: exported.fileURL,
                                    totalBytes: exported.sizeBytes,
                                    accessToken: tokens.accessToken, onStage: onStage)
        }

        onStage(.finishing)
        if let poster = exported.posterJPEG {
            // best effort: un póster fallido jamás bloquea el link
            try? await api.uploadPoster(videoID: created.video_id, jpeg: poster,
                                        accessToken: tokens.accessToken)
        }
        let done = try await api.complete(videoID: created.video_id,
                                          accessToken: tokens.accessToken)
        guard let watchURL = URL(string: done.watch_url) else {
            throw CloudError.network("bad watch_url")
        }
        return CloudUpload(slug: done.slug, watchURL: watchURL,
                           expiresAt: done.expires_at.flatMap(Self.iso.date(of:)))
    }

    // ---- internals -------------------------------------------------------

    private func uploadInParts(_ created: CloudAPI.CreatedUpload, fileURL: URL,
                               totalBytes: Int64, accessToken: String,
                               onStage: @escaping @Sendable (CloudShareStage) -> Void) async throws {
        guard let uploadID = created.upload_id else { throw CloudError.network("no upload_id") }
        let partSize = created.part_size ?? Self.partSize
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var parts: [(Int, String)] = []
        var sent: Int64 = 0
        var partNumber = 1
        while true {
            guard let chunk = try handle.read(upToCount: partSize), !chunk.isEmpty else { break }
            let part = try await api.uploadPart(videoID: created.video_id, uploadID: uploadID,
                                                partNumber: partNumber, body: chunk,
                                                accessToken: accessToken)
            parts.append((part.part_number, part.etag))
            sent += Int64(chunk.count)
            partNumber += 1
            onStage(.uploading(Double(sent) / Double(max(totalBytes, 1))))
        }
        try await api.completeMultipart(videoID: created.video_id, uploadID: uploadID,
                                        parts: parts, accessToken: accessToken)
    }

    /// A session that is valid right now, refreshing behind the scenes.
    private func validTokens() async throws -> CloudTokens {
        guard let current = tokens else { throw CloudError.notSignedIn }
        if current.expiresAt > Date().addingTimeInterval(60) { return current }
        do {
            let fresh = try await api.refresh(current)
            tokens = fresh
            store.save(fresh)
            return fresh
        } catch {
            tokens = nil
            store.clear()
            throw CloudError.notSignedIn
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension ISO8601DateFormatter {
    /// Tolerante: el API a veces trae fracciones de segundo y a veces no.
    func date(of string: String) -> Date? {
        if let date = date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: string)
    }
}
