import Foundation

/// Metadata for a whisper.cpp model, including its name, download URL,
/// approximate file size, and whether it supports only English.
struct WhisperModel: Identifiable {
    let id: String
    let name: String
    let displaySize: String
    let isEnglishOnly: Bool

    /// The expected filename on disk (e.g., "ggml-tiny.bin").
    var filename: String {
        "ggml-\(name).bin"
    }

    /// The remote URL to download this model from Hugging Face.
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    /// The directory where all whisper models are stored.
    static let storageDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VoxScribe Models")
    }()

    /// The full local file path for this model.
    var localFilePath: URL {
        WhisperModel.storageDirectory.appendingPathComponent(filename)
    }

    /// Whether this model has been downloaded and exists on disk.
    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localFilePath.path)
    }

    /// All available whisper models in order from smallest to largest.
    static let allModels: [WhisperModel] = [
        WhisperModel(id: "tiny.en", name: "tiny.en", displaySize: "~75 MB", isEnglishOnly: true),
        WhisperModel(id: "tiny", name: "tiny", displaySize: "~75 MB", isEnglishOnly: false),
        WhisperModel(id: "base.en", name: "base.en", displaySize: "~142 MB", isEnglishOnly: true),
        WhisperModel(id: "base", name: "base", displaySize: "~142 MB", isEnglishOnly: false),
        WhisperModel(id: "small.en", name: "small.en", displaySize: "~466 MB", isEnglishOnly: true),
        WhisperModel(id: "small", name: "small", displaySize: "~466 MB", isEnglishOnly: false),
        WhisperModel(id: "medium.en", name: "medium.en", displaySize: "~1.5 GB", isEnglishOnly: true),
        WhisperModel(id: "medium", name: "medium", displaySize: "~1.5 GB", isEnglishOnly: false),
        WhisperModel(id: "large-v3", name: "large-v3", displaySize: "~3.1 GB", isEnglishOnly: false),
    ]
}
