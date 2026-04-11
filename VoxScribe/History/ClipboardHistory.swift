import Foundation

/// Manages a persisted list of transcription history entries.
///
/// Entries are stored in memory and written to a JSON file on disk after
/// each mutation. The list is capped at a configurable limit, with the
/// oldest entries pruned first.
///
/// - Parameters:
///   - fileURL: The file URL where history is persisted as JSON.
///   - limit: The maximum number of entries to retain.
final class ClipboardHistory {
    private(set) var entries: [HistoryEntry]
    private let fileURL: URL
    private var limit: Int

    /// Creates a ClipboardHistory, loading existing entries from disk if available.
    ///
    /// - Parameters:
    ///   - fileURL: Path to the JSON persistence file.
    ///   - limit: Maximum number of entries to keep.
    init(fileURL: URL, limit: Int) {
        self.fileURL = fileURL
        self.limit = limit
        self.entries = []
        loadFromDisk()
    }

    /// Adds a new transcription to the history.
    ///
    /// The entry is inserted at the front (most recent first). If the total
    /// count exceeds the limit, the oldest entries are removed. The updated
    /// list is persisted to disk.
    ///
    /// - Parameter text: The full transcription text.
    func addEntry(text: String) {
        let entry = HistoryEntry(text: text, timestamp: Date())
        entries.insert(entry, at: 0)
        pruneToLimit()
        saveToDisk()
    }

    /// Removes all history entries and deletes the persistence file.
    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Updates the maximum entry limit and prunes excess entries.
    ///
    /// - Parameter newLimit: The new maximum number of entries to retain.
    func updateLimit(_ newLimit: Int) {
        limit = newLimit
        pruneToLimit()
        saveToDisk()
    }

    /// Removes entries beyond the configured limit, keeping the most recent.
    private func pruneToLimit() {
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
    }

    /// Writes the current entries to the JSON file on disk.
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    /// Loads entries from the JSON file on disk if it exists.
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            NSLog("Failed to load clipboard history: \(error.localizedDescription)")
            entries = []
        }
    }
}
