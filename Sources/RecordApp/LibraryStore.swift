import Foundation
import AppKit
import AVFoundation

/// One recording on disk.
struct RecordingItem: Identifiable, Equatable {
    let id: URL // the file URL is the identity
    let name: String
    let date: Date
    let sizeBytes: Int64
    var duration: TimeInterval?
    var thumbnail: NSImage?

    static func == (a: RecordingItem, b: RecordingItem) -> Bool {
        a.id == b.id && a.duration == b.duration && (a.thumbnail === b.thumbnail)
    }

    var durationText: String {
        guard let duration else { return "…" }
        let s = Int(duration.rounded())
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    /// "today, 9:41" / "yesterday" / "Aug 18" — the library's friendly date.
    var whenText: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let t = DateFormatter()
            t.timeStyle = .short; t.dateStyle = .none
            return LF("lib.today", t.string(from: date))
        }
        if cal.isDateInYesterday(date) { return L("lib.yesterday") }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }
}

/// The recordings library: the real contents of the destination folder
/// (Grabi *.mov), newest first. Durations and thumbnails load lazily in the
/// background; thumbnails are cached in memory per file+mtime.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [RecordingItem] = []
    @Published private(set) var totalBytes: Int64 = 0
    /// Recording finished this session — gets the "NEW" badge.
    @Published var newestURL: URL?

    private var folder: URL?
    private var thumbCache: [String: NSImage] = [:]
    private var generation = 0

    func refresh(folder: URL) {
        self.folder = folder
        generation += 1
        let gen = generation
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        var fresh: [RecordingItem] = []
        for url in urls where url.pathExtension.lowercased() == "mov" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            fresh.append(RecordingItem(
                id: url,
                name: url.deletingPathExtension().lastPathComponent,
                date: values?.contentModificationDate ?? .distantPast,
                sizeBytes: Int64(values?.fileSize ?? 0),
                duration: nil,
                thumbnail: nil))
        }
        fresh.sort { $0.date > $1.date }
        items = fresh
        totalBytes = fresh.reduce(0) { $0 + $1.sizeBytes }
        loadDetails(for: fresh, generation: gen)
    }

    private func loadDetails(for list: [RecordingItem], generation gen: Int) {
        for item in list {
            let key = "\(item.id.path)#\(item.date.timeIntervalSince1970)"
            if let cached = thumbCache[key] {
                apply(url: item.id, gen: gen) { $0.thumbnail = cached }
            }
            Task.detached(priority: .utility) { [weak self] in
                let asset = AVURLAsset(url: item.id)
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                await self?.apply(url: item.id, gen: gen) { $0.duration = duration }
                if await self?.cachedThumb(key) == nil {
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 480, height: 480)
                    let at = CMTime(seconds: min(0.5, duration / 2), preferredTimescale: 600)
                    if let cg = try? generator.copyCGImage(at: at, actualTime: nil) {
                        let image = NSImage(cgImage: cg, size: .zero)
                        await self?.storeThumb(image, key: key, url: item.id, gen: gen)
                    }
                }
            }
        }
    }

    private func cachedThumb(_ key: String) -> NSImage? { thumbCache[key] }

    private func storeThumb(_ image: NSImage, key: String, url: URL, gen: Int) {
        thumbCache[key] = image
        apply(url: url, gen: gen) { $0.thumbnail = image }
    }

    private func apply(url: URL, gen: Int, _ mutate: (inout RecordingItem) -> Void) {
        guard gen == generation, let idx = items.firstIndex(where: { $0.id == url }) else { return }
        mutate(&items[idx])
    }

    var metaText: String {
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return items.count == 1 ? LF("lib.meta.one", size) : LF("lib.meta", items.count, size)
    }

    // MARK: - Actions

    func play(_ item: RecordingItem) {
        NSWorkspace.shared.open(item.id)
    }

    func revealInFinder(_ item: RecordingItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.id])
    }

    /// Copies the FILE to the pasteboard: ready to paste into Messages/Slack.
    func copy(_ item: RecordingItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.id as NSURL])
    }

    /// Moves to Trash (recoverable) and refreshes.
    func trash(_ item: RecordingItem) {
        try? FileManager.default.trashItem(at: item.id, resultingItemURL: nil)
        if newestURL == item.id { newestURL = nil }
        if let folder { refresh(folder: folder) }
    }
}
