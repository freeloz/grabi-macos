import AVFoundation
import AppKit
import GrabiDomain

/// Grabi records HEVC .mov with the microphone and the system audio on two
/// separate tracks — great for editing, useless in a browser (Firefox has no
/// HEVC; browsers play one audio track). Sharing needs a web-safe variant:
/// H.264 + a single mixed AAC track + faststart. This is that remux, done
/// locally with AVFoundation — no server compute, ever.
struct WebSafeExporter: Sendable {
    struct Output: Sendable {
        let fileURL: URL
        let durationS: Int
        let sizeBytes: Int64
        let posterJPEG: Data?
    }

    func export(_ sourceURL: URL,
                onProgress: @escaping @Sendable (Double) -> Void) async throws -> Output {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)

        // 1080p keeps a screen recording sharp; the preset transcodes to
        // H.264 and mixes every audio track into one AAC stereo track.
        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPreset1920x1080
        ) else { throw CloudError.exportFailed }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("grabi-cloud-\(UUID().uuidString).mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true // moov al frente: seek instantáneo

        let progressTask = Task {
            while !Task.isCancelled {
                onProgress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        await session.export()
        progressTask.cancel()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw CloudError.exportFailed
        }
        onProgress(1)

        let sizeBytes = (try? FileManager.default
            .attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        return Output(
            fileURL: outputURL,
            durationS: Int(duration.seconds.rounded()),
            sizeBytes: sizeBytes ?? 0,
            posterJPEG: try? await poster(for: asset, duration: duration)
        )
    }

    /// One representative frame (10% in — past the empty first instants)
    /// as JPEG: the og:image of the share page and the <video> poster.
    private func poster(for asset: AVAsset, duration: CMTime) async throws -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let time = CMTime(seconds: max(0.5, duration.seconds * 0.1), preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
