import Foundation

// The seams. Everything the domain needs from the outside world is one of
// these protocols; the app wires real adapters, the tests wire fakes.

/// Captures and (optionally) writes. One pipeline serves the preview and
/// the recording: the plan says which.
public protocol CaptureEnginePort: AnyObject, Sendable {
    var state: RecordingState { get }
    var isPreviewing: Bool { get }

    func startPreview(_ plan: RecordingPlan) async throws
    func stopPreview() async
    func startRecording(_ plan: RecordingPlan) async throws
    func stopRecording() async throws -> URL
    func pause()
    func resume()
    /// Live changes that must not interrupt the recording.
    func update(cameraLayout: CameraLayout)
    func setMicrophoneMuted(_ muted: Bool)
    func setCameraHidden(_ hidden: Bool) async
}

/// The microphone level while framing — a session of its own, so the
/// recording pipeline stays untouched.
public protocol MicrophoneMonitorPort: AnyObject, Sendable {
    func start(deviceID: String?) async
    func stop() async
}

/// Cameras and microphones connected right now.
public protocol DeviceDirectoryPort: Sendable {
    func cameras() -> [CaptureDeviceInfo]
    func microphones() -> [CaptureDeviceInfo]
}

/// Displays and windows that can be captured.
public protocol ScreenContentPort: Sendable {
    func availableContent() async throws -> ShareableContent
}

/// What macOS lets us do.
public protocol PermissionsPort: Sendable {
    func report(requestingAccess: Bool) async -> PermissionReport
    func openSystemSettings(for source: RecordingSource)
}

/// The recordings on disk.
public protocol RecordingLibraryPort: Sendable {
    func recordings(in folder: URL) -> [Recording]
    func duration(of recording: Recording) async -> TimeInterval?
    func moveToTrash(_ recording: Recording) throws
    func reveal(_ recording: Recording)
    func play(_ recording: Recording)
    func copyToPasteboard(_ recording: Recording)
}

/// Preferences that survive relaunches.
public protocol PreferencesPort: AnyObject, Sendable {
    var destinationFolder: URL { get set }
    var quality: RecordingQuality { get set }
    var cameraLayout: CameraLayout { get set }
    var devices: DeviceSelection { get set }
    var language: AppLanguage { get set }
    var quickAccessEnabled: Bool { get set }
    var onboardingDone: Bool { get set }
}

/// Applies the chosen language to the running app.
public protocol LocalizationPort: Sendable {
    func apply(_ language: AppLanguage)
}

/// Tells the user a recording is ready.
public protocol NotifierPort: Sendable {
    func recordingFinished(url: URL, duration: TimeInterval)
}

/// Time, injectable so tests do not sleep.
public protocol ClockPort: Sendable {
    func now() -> Date
}

/// Grabi Cloud — optional sharing. The adapter owns tokens, export and
/// upload; the domain only cares that a recording becomes a link.
public protocol CloudPort: AnyObject, Sendable {
    /// nil when nobody is signed in (the app's default state, forever).
    func account() async -> CloudAccount?
    func signIn(email: String, password: String) async throws -> CloudAccount
    /// true = signed in right away; false = confirmation email pending.
    func signUp(email: String, password: String, locale: String) async throws -> Bool
    func signOut() async
    /// Export web-safe, upload, and return the share link.
    func share(_ recording: Recording, title: String,
               onStage: @escaping @Sendable (CloudShareStage) -> Void) async throws -> CloudUpload

    /// Which identity providers the server has actually enabled, so the UI
    /// never shows a button that errors out when tapped.
    func identityProviders() async -> [CloudIdentityProvider]

    /// Sign-in with an identity provider: the URL to open in the browser;
    /// the flow comes back via the app's URL scheme and lands in
    /// `adoptSession`. One entry point for all providers — adding one is a
    /// new case in `CloudIdentityProvider`, not a new port method.
    func oauthAuthorizeURL(provider: CloudIdentityProvider) -> URL
    /// Email sign-in also happens in the browser (that's where the captcha
    /// widget lives); same round trip back into `adoptSession`.
    func emailSignInURL() -> URL
    /// Adopt tokens delivered by the OAuth callback.
    func adoptSession(accessToken: String, refreshToken: String,
                      expiresIn: Double) async throws -> CloudAccount
}
