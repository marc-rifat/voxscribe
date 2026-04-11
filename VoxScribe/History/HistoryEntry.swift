import Foundation

/// A single transcription result stored in clipboard history.
///
/// Contains the full transcription text, the timestamp when it was created,
/// and computed properties for display in the menu bar submenu.
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date

    /// Creates a new history entry.
    ///
    /// - Parameters:
    ///   - text: The full transcription text.
    ///   - timestamp: When the transcription was created.
    ///   - id: Unique identifier. Defaults to a new UUID.
    init(text: String, timestamp: Date, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }

    /// A truncated preview of the transcription text (first 50 characters + "...").
    var preview: String {
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(50)) + "..."
    }

    /// A human-readable relative timestamp (e.g., "5 min ago", "2 hr ago").
    var relativeTimestamp: String {
        let elapsed = Int(Date().timeIntervalSince(timestamp))
        switch elapsed {
        case ..<60:
            return "just now"
        case 60..<3600:
            let minutes = elapsed / 60
            return "\(minutes) min ago"
        case 3600..<86400:
            let hours = elapsed / 3600
            return "\(hours) hr ago"
        default:
            let days = elapsed / 86400
            return "\(days) day ago"
        }
    }
}
