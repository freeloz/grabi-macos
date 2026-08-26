import Foundation
import GrabiDomain

/// Share a recording to Grabi Cloud: signed-in first, then the adapter does
/// export → upload → link. The use case owns the policy; the adapter, the
/// plumbing. The returned link is what the app copies to the pasteboard.
public struct ShareToCloudUseCase: Sendable {
    private let cloud: CloudPort

    public init(cloud: CloudPort) {
        self.cloud = cloud
    }

    public func callAsFunction(
        _ recording: Recording,
        title: String? = nil,
        onStage: @escaping @Sendable (CloudShareStage) -> Void = { _ in }
    ) async throws -> CloudUpload {
        guard await cloud.account() != nil else { throw CloudError.notSignedIn }
        // The recording's name is the natural default title — the student
        // shouldn't have to type anything to get their link.
        let finalTitle = (title?.isEmpty == false ? title! : recording.name)
        return try await cloud.share(recording, title: finalTitle, onStage: onStage)
    }
}
