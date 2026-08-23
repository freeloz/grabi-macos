import Foundation
import GrabiDomain

/// The recordings folder as the app sees it: newest first, with the sizes
/// and durations the UI shows.
public struct ListRecordingsUseCase: Sendable {
    private let library: RecordingLibraryPort

    public init(library: RecordingLibraryPort) { self.library = library }

    public func callAsFunction(in folder: URL) -> [Recording] {
        library.recordings(in: folder).sorted { $0.date > $1.date }
    }

    public func totalBytes(_ recordings: [Recording]) -> Int64 {
        recordings.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// Deleting means the Trash: recoverable, never a silent shred.
public struct DeleteRecordingUseCase: Sendable {
    private let library: RecordingLibraryPort

    public init(library: RecordingLibraryPort) { self.library = library }

    public func callAsFunction(_ recording: Recording) throws {
        try library.moveToTrash(recording)
    }
}
