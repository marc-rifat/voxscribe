import Foundation

/// Swift wrapper around the whisper.cpp C API for audio transcription.
///
/// Manages the lifecycle of a whisper model context, providing methods
/// to load models, run transcription on PCM audio files, and free resources.
/// All transcription runs on a background queue; results are delivered
/// on the main queue via completion closures.
///
/// - Important: Only one model is loaded at a time. Switching models
///   frees the previous context before loading the new one.
final class TranscriptionEngine {
    private var whisperContext: OpaquePointer?
    private let transcriptionQueue = DispatchQueue(
        label: "com.voxscribe.transcription",
        qos: .userInitiated
    )
    private(set) var isTranscribing = false
    private(set) var loadedModelName: String?

    /// Loads a whisper model from disk into memory.
    ///
    /// If another model is already loaded, it is freed first.
    ///
    /// - Parameter model: The whisper model whose local file should be loaded.
    /// - Throws: `TranscriptionError.modelLoadFailed` if the file cannot be
    ///   loaded by whisper.cpp.
    func loadModel(_ model: WhisperModel) throws {
        unloadModel()
        let path = model.localFilePath.path
        var params = whisper_context_default_params()
        guard let context = whisper_init_from_file_with_params(path, params) else {
            throw TranscriptionError.modelLoadFailed(model.name)
        }
        whisperContext = context
        loadedModelName = model.name
        NSLog("Loaded whisper model: \(model.name)")
    }

    /// Frees the currently loaded model from memory.
    func unloadModel() {
        if let context = whisperContext {
            whisper_free(context)
            whisperContext = nil
            loadedModelName = nil
            NSLog("Unloaded whisper model")
        }
    }

    /// Transcribes a 16kHz mono PCM audio file to text.
    ///
    /// The transcription runs on a background queue. The completion handler
    /// is called on the main queue with either the transcribed text or an error.
    ///
    /// - Parameters:
    ///   - audioFileURL: Path to a 16kHz mono Float32 PCM file (no header).
    ///   - completion: Called on the main queue with the transcription result.
    func transcribe(
        audioFileURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let context = whisperContext else {
            DispatchQueue.main.async {
                completion(.failure(TranscriptionError.noModelLoaded))
            }
            return
        }

        isTranscribing = true

        transcriptionQueue.async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isTranscribing = false
                }
            }

            do {
                let samples = try self?.loadPCMSamples(from: audioFileURL) ?? []
                if samples.isEmpty {
                    DispatchQueue.main.async {
                        completion(.failure(TranscriptionError.emptyAudio))
                    }
                    return
                }

                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.language = nil  // auto-detect language
                params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
                params.print_progress = false
                params.print_timestamps = false

                let result = samples.withUnsafeBufferPointer { bufferPointer in
                    whisper_full(
                        context,
                        params,
                        bufferPointer.baseAddress,
                        Int32(bufferPointer.count)
                    )
                }

                guard result == 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(TranscriptionError.transcriptionFailed))
                    }
                    return
                }

                let segmentCount = whisper_full_n_segments(context)
                var transcription = ""
                for i in 0..<segmentCount {
                    if let cString = whisper_full_get_segment_text(context, i) {
                        transcription += String(cString: cString)
                    }
                }

                let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion(.success(trimmed))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Reads raw Float32 PCM samples from a file.
    ///
    /// - Parameter url: Path to the PCM audio file.
    /// - Returns: An array of Float32 samples.
    /// - Throws: An error if the file cannot be read.
    private func loadPCMSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let sampleCount = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { buffer in
            data.copyBytes(to: buffer)
        }
        return samples
    }

    deinit {
        unloadModel()
    }
}

/// Errors that can occur during transcription operations.
enum TranscriptionError: LocalizedError {
    case modelLoadFailed(String)
    case noModelLoaded
    case emptyAudio
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let name):
            return "Failed to load whisper model '\(name)'."
        case .noModelLoaded:
            return "No whisper model is loaded."
        case .emptyAudio:
            return "Audio file contains no samples."
        case .transcriptionFailed:
            return "Transcription failed."
        }
    }
}
