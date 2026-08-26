import Foundation
import GrabiDomain

// The HTTP truth of Grabi Cloud, and nothing else: Supabase Auth for
// identity, api.grabi.net for uploads/links. No SDKs — two REST APIs and
// URLSession. Session policy (Keychain, refresh) lives in GrabiCloudAdapter.

public struct CloudEnvironment: Sendable {
    let apiBase: URL
    let supabaseURL: URL
    let supabaseAnonKey: String

    public static let production = CloudEnvironment(
        apiBase: URL(string: "https://api.grabi.net")!,
        supabaseURL: URL(string: "https://ynjwtzhlzhpqgbkcoplc.supabase.co")!,
        // Anon/publishable key: public by design; RLS protects the data.
        supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inluand0emhsemhwcWdia2NvcGxjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc3MjE1MTcsImV4cCI6MjEwMzI5NzUxN30.I0b4vlKrgPYqqrorPcIxGdKXHi8j288o9F-BKcQi0HA"
    )

    public static let staging = CloudEnvironment(
        apiBase: URL(string: "https://grabi-cloud-api-staging.freeloz.workers.dev")!,
        supabaseURL: URL(string: "https://gullyxdyyiulchcsafps.supabase.co")!,
        supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd1bGx5eGR5eWl1bGNoY3NhZnBzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc3MjE1MTYsImV4cCI6MjEwMzI5NzUxNn0.JW-PdMXWDq5y7NpTgg3iaqkiYS3m9wlutGLW4xDUsBk"
    )

    /// `defaults write net.grabi.Grabi GrabiCloudEnvironment staging`
    public static var current: CloudEnvironment {
        UserDefaults.standard.string(forKey: "GrabiCloudEnvironment") == "staging"
            ? .staging : .production
    }
}

/// Tokens as Supabase hands them out.
struct CloudTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let email: String
}

struct CloudAPI: Sendable {
    let env: CloudEnvironment
    private let session: URLSession

    init(env: CloudEnvironment = .current, session: URLSession = .shared) {
        self.env = env
        self.session = session
    }

    // ---- Supabase Auth ---------------------------------------------------

    private struct AuthResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let user: AuthUser?
        struct AuthUser: Decodable { let email: String? }
    }

    func signIn(email: String, password: String) async throws -> CloudTokens {
        try await authRequest(path: "token?grant_type=password",
                              body: ["email": email, "password": password],
                              failure: CloudError.badCredentials)
    }

    func refresh(_ tokens: CloudTokens) async throws -> CloudTokens {
        try await authRequest(path: "token?grant_type=refresh_token",
                              body: ["refresh_token": tokens.refreshToken],
                              failure: CloudError.notSignedIn)
    }

    /// nil = account created but the confirmation email is pending.
    func signUp(email: String, password: String, locale: String) async throws -> CloudTokens? {
        var request = URLRequest(url: env.supabaseURL.appendingPathComponent("auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue(env.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "data": ["locale": locale],
        ])
        let (data, response) = try await send(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CloudError.network("signup \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let access = auth.access_token, let refreshToken = auth.refresh_token else { return nil }
        return CloudTokens(accessToken: access, refreshToken: refreshToken,
                           expiresAt: Date().addingTimeInterval(auth.expires_in ?? 3600),
                           email: email)
    }

    private func authRequest(path: String, body: [String: String],
                             failure: CloudError) async throws -> CloudTokens {
        var request = URLRequest(url: URL(string: "auth/v1/\(path)", relativeTo: env.supabaseURL)!)
        request.httpMethod = "POST"
        request.setValue(env.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure }
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        guard let access = auth.access_token, let refreshToken = auth.refresh_token else { throw failure }
        return CloudTokens(accessToken: access, refreshToken: refreshToken,
                           expiresAt: Date().addingTimeInterval(auth.expires_in ?? 3600),
                           email: auth.user?.email ?? "")
    }

    // ---- Grabi Cloud API -------------------------------------------------

    struct Me: Decodable, Sendable { let plan: String }
    struct CreatedUpload: Decodable, Sendable {
        let video_id: String
        let slug: String
        let mode: String
        let upload_id: String?
        let part_size: Int?
    }
    struct Part: Decodable, Sendable { let part_number: Int, etag: String }
    struct Completed: Decodable, Sendable {
        let slug: String
        let watch_url: String
        let expires_at: String?
    }
    private struct APIError: Decodable { let error: String? }

    func me(accessToken: String) async throws -> Me {
        try await api("GET", "/me", accessToken: accessToken)
    }

    func createUpload(title: String, durationS: Int, sizeBytes: Int64,
                      accessToken: String) async throws -> CreatedUpload {
        try await api("POST", "/uploads", accessToken: accessToken, json: [
            "title": title, "duration_s": durationS, "size_bytes": sizeBytes,
        ])
    }

    func uploadFile(videoID: String, fileURL: URL, accessToken: String) async throws {
        var request = URLRequest(url: env.apiBase.appendingPathComponent("uploads/\(videoID)/file"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        try check(response, data)
    }

    func uploadPart(videoID: String, uploadID: String, partNumber: Int, body: Data,
                    accessToken: String) async throws -> Part {
        var request = URLRequest(url: env.apiBase
            .appendingPathComponent("uploads/\(videoID)/parts/\(partNumber)"))
        request.url = request.url.map { url in
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "uploadId", value: uploadID)]
            return comps.url!
        }
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.upload(for: request, from: body)
        try check(response, data)
        return try JSONDecoder().decode(Part.self, from: data)
    }

    func completeMultipart(videoID: String, uploadID: String, parts: [(Int, String)],
                           accessToken: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await api("POST", "/uploads/\(videoID)/multipart-complete",
                                     accessToken: accessToken, json: [
            "upload_id": uploadID,
            "parts": parts.map { ["part_number": $0.0, "etag": $0.1] },
        ])
    }

    func uploadPoster(videoID: String, jpeg: Data, accessToken: String) async throws {
        var request = URLRequest(url: env.apiBase.appendingPathComponent("uploads/\(videoID)/poster"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, from: jpeg)
        try check(response, data)
    }

    func complete(videoID: String, accessToken: String) async throws -> Completed {
        try await api("POST", "/uploads/\(videoID)/complete", accessToken: accessToken, json: [:])
    }

    // ---- plumbing --------------------------------------------------------

    private func api<T: Decodable>(_ method: String, _ path: String, accessToken: String,
                                   json: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: env.apiBase.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await send(request)
        try check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch { throw CloudError.network(error.localizedDescription) }
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CloudError.network("no response") }
        guard !(200...299).contains(http.statusCode) else { return }
        let code = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "\(http.statusCode)"
        if http.statusCode == 401 { throw CloudError.notSignedIn }
        if code.hasPrefix("upgrade_required_") {
            throw CloudError.planLimit(String(code.dropFirst("upgrade_required_".count)))
        }
        throw CloudError.network(code)
    }
}
