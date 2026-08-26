import Foundation

// Grabi Cloud is strictly opt-in: the app works forever without an account,
// and nothing leaves the Mac unless the user taps "Share to Grabi Cloud".
// These types are the whole vocabulary the rest of the app needs for that.

/// A signed-in Grabi Cloud account.
public struct CloudAccount: Equatable, Sendable {
    public let email: String
    /// "free" | "pro" | "student" — the server is the authority.
    public let plan: String

    public init(email: String, plan: String) {
        self.email = email
        self.plan = plan
    }
}

/// The result of sharing a recording: the link that gets pasted into
/// a deliverable. This IS the product.
public struct CloudUpload: Equatable, Sendable {
    public let slug: String
    public let watchURL: URL
    /// nil on paid plans: the video never expires.
    public let expiresAt: Date?

    public init(slug: String, watchURL: URL, expiresAt: Date?) {
        self.slug = slug
        self.watchURL = watchURL
        self.expiresAt = expiresAt
    }
}

/// How far along a share is — drives the progress UI.
public enum CloudShareStage: Equatable, Sendable {
    case exporting(Double)
    case uploading(Double)
    case finishing
}

/// Everything that can go wrong sharing, in words the UI can translate.
public enum CloudError: Error, Equatable, Sendable {
    case notSignedIn
    case badCredentials
    case emailNotConfirmed
    /// Free-plan limits: "duration" | "count" | "storage".
    case planLimit(String)
    case exportFailed
    case network(String)
}
