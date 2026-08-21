import Foundation
import AppKit
import UserNotifications
import AVFoundation

/// Native post-recording notification (Phase 3 §05): thumbnail + "View" /
/// "Copy link". Respects Do Not Disturb. The file is already saved by the
/// time the notification is seen.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private weak var model: GrabiAppModel?
    private var lastURL: URL?

    func configure(model: GrabiAppModel) {
        self.model = model
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let ver = UNNotificationAction(identifier: "VIEW", title: L("app.notif.view"), options: [.foreground])
        let copiar = UNNotificationAction(identifier: "COPY", title: L("app.notif.copy"), options: [])
        let category = UNNotificationCategory(
            identifier: "GRABI_DONE", actions: [ver, copiar], intentIdentifiers: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func showRecordingDone(url: URL, duration: TimeInterval, model: GrabiAppModel) {
        lastURL = url
        let total = Int(duration)
        let durText = String(format: "%d:%02d", total / 60, total % 60)
        let sizeText = fileSizeText(url: url)

        let content = UNMutableNotificationContent()
        content.title = L("app.notif.title")
        content.body = "\(durText)\(sizeText.map { " · \($0)" } ?? "") · \(LF("app.notif.en", url.deletingLastPathComponent().lastPathComponent))"
        content.categoryIdentifier = "GRABI_DONE"
        content.sound = nil

        // Thumbnail from the first second of the video.
        if let thumbnail = makeThumbnail(url: url),
           let attachment = try? UNNotificationAttachment(identifier: "thumb", url: thumbnail) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: url.lastPathComponent, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func fileSizeText(url: URL) -> String? {
        guard let bytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else { return nil }
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }

    private func makeThumbnail(url: URL) -> URL? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grabi-thumb-\(UUID().uuidString).png")
        try? data.write(to: tmp)
        return tmp
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let url = lastURL else { return }
        switch response.actionIdentifier {
        case "VIEW":
            NSWorkspace.shared.open(url)
        case "COPY":
            // "Copy link" copies the file to the pasteboard, ready to
            // paste into Messages or Slack.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        default:
            // Click on the body → reveal in Finder.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
