import Foundation
import AppKit
import UserNotifications
import AVFoundation

/// Notificación nativa post-grabación (Fase 3 §05): miniatura + «Ver» /
/// «Copiar enlace». Respeta No molestar. El archivo ya está guardado cuando
/// se ve la notificación.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private weak var model: GrabiAppModel?
    private var lastURL: URL?

    func configure(model: GrabiAppModel) {
        self.model = model
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let ver = UNNotificationAction(identifier: "VER", title: "Ver", options: [.foreground])
        let copiar = UNNotificationAction(identifier: "COPIAR", title: "Copiar enlace", options: [])
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
        content.title = "¡Quedó! Tu grabación está lista"
        content.body = "\(durText)\(sizeText.map { " · \($0)" } ?? "") · en \(url.deletingLastPathComponent().lastPathComponent)"
        content.categoryIdentifier = "GRABI_DONE"
        content.sound = nil

        // Miniatura del primer segundo del video.
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
        case "VER":
            NSWorkspace.shared.open(url)
        case "COPIAR":
            // «Copiar enlace» copia el archivo al portapapeles, listo para
            // pegar en Mensajes o Slack.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        default:
            // Clic en el cuerpo → mostrar en Finder.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
