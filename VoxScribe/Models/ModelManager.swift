import Foundation

/// Manages downloading, deleting, and querying whisper model files on disk.
///
/// Models are stored as `.bin` files in a configurable storage directory
/// (defaults to `~/Documents/VoxScribe Models/`). Downloads are performed
/// via `URLSession` with progress reporting through a closure.
final class ModelManager: ObservableObject {
    private let storageDirectory: URL
    @Published var activeDownloads: [String: Double] = [:]

    /// Creates a ModelManager with a custom storage directory.
    ///
    /// - Parameter storageDirectory: Where to store downloaded model files.
    ///   Defaults to `WhisperModel.storageDirectory`.
    init(storageDirectory: URL = WhisperModel.storageDirectory) {
        self.storageDirectory = storageDirectory
        ensureStorageDirectoryExists()
    }

    /// Returns all models that have been downloaded and exist on disk.
    ///
    /// - Returns: An array of `WhisperModel` values whose files are present
    ///   in the storage directory, ordered from smallest to largest.
    func downloadedModels() -> [WhisperModel] {
        WhisperModel.allModels.filter { model in
            let path = storageDirectory.appendingPathComponent(model.filename)
            return FileManager.default.fileExists(atPath: path.path)
        }
    }

    /// Returns the smallest downloaded model, or nil if no models are downloaded.
    ///
    /// - Returns: The smallest available `WhisperModel`, or nil.
    func smallestDownloadedModel() -> WhisperModel? {
        downloadedModels().first
    }

    /// Deletes a downloaded model file from disk.
    ///
    /// - Parameter model: The model to delete.
    /// - Throws: An error if the file does not exist or cannot be removed.
    func deleteModel(_ model: WhisperModel) throws {
        let path = storageDirectory.appendingPathComponent(model.filename)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ModelManagerError.modelNotFound(model.name)
        }
        try FileManager.default.removeItem(at: path)
    }

    /// Downloads a model from its remote URL to the storage directory.
    ///
    /// Progress is reported via the `activeDownloads` published property,
    /// keyed by model name (0.0 to 1.0).
    ///
    /// - Parameters:
    ///   - model: The model to download.
    ///   - completion: Called on the main queue when the download finishes
    ///     or fails. Receives a `Result<URL, Error>` with the local file path.
    func downloadModel(
        _ model: WhisperModel,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let destinationPath = storageDirectory.appendingPathComponent(model.filename)
        let delegate = DownloadDelegate(
            modelName: model.name,
            destination: destinationPath,
            manager: self,
            completion: completion
        )
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        let task = session.downloadTask(with: model.downloadURL)
        DispatchQueue.main.async {
            self.activeDownloads[model.name] = 0.0
        }
        task.resume()
    }

    /// Checks whether a specific model file exists on disk.
    ///
    /// - Parameter model: The model to check.
    /// - Returns: `true` if the model file is present in the storage directory.
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = storageDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Creates the storage directory if it does not already exist.
    private func ensureStorageDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }
}

/// Errors specific to model management operations.
enum ModelManagerError: LocalizedError {
    case modelNotFound(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model '\(name)' not found on disk."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}

/// URLSession delegate that handles download progress and file relocation.
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let modelName: String
    let destination: URL
    weak var manager: ModelManager?
    let completion: (Result<URL, Error>) -> Void

    init(
        modelName: String,
        destination: URL,
        manager: ModelManager,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.modelName = modelName
        self.destination = destination
        self.manager = manager
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            DispatchQueue.main.async {
                self.manager?.activeDownloads.removeValue(forKey: self.modelName)
                self.completion(.success(self.destination))
            }
        } catch {
            DispatchQueue.main.async {
                self.manager?.activeDownloads.removeValue(forKey: self.modelName)
                self.completion(.failure(error))
            }
        }
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.manager?.activeDownloads[self.modelName] = progress
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            DispatchQueue.main.async {
                self.manager?.activeDownloads.removeValue(forKey: self.modelName)
                self.completion(.failure(error))
            }
        }
        session.invalidateAndCancel()
    }
}
