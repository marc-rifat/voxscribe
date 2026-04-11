import AVFoundation
import Foundation

/// Records audio from a selected input device to a temporary 16kHz mono PCM file.
///
/// Uses `AVAudioEngine` to capture audio and writes samples to disk in real time
/// to minimize memory usage. The engine tap is removed and the engine stopped
/// as soon as recording ends.
///
/// - Important: Callers must request microphone permission before starting
///   a recording.
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var outputFile: FileHandle?
    private var tempFileURL: URL?
    private(set) var isRecording = false

    /// The CoreAudio device ID to record from, or nil for the system default.
    var inputDeviceID: AudioDeviceID?

    /// Starts recording audio to a temporary PCM file.
    ///
    /// Audio is captured at 16kHz mono Float32, which is the format whisper.cpp
    /// expects. The temporary file is created in `NSTemporaryDirectory()`.
    ///
    /// - Throws: `AudioRecorderError.alreadyRecording` if a recording is in progress,
    ///   or `AudioRecorderError.engineStartFailed` if the audio engine cannot start.
    func startRecording() throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let engine = AVAudioEngine()

        if let deviceID = inputDeviceID {
            setInputDevice(deviceID, on: engine)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatConversionFailed
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voxscribe_recording_\(UUID().uuidString).pcm")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.convertAndWrite(
                buffer: buffer,
                converter: converter,
                targetFormat: targetFormat,
                fileHandle: fileHandle
            )
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            fileHandle.closeFile()
            try? FileManager.default.removeItem(at: tempURL)
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }

        audioEngine = engine
        outputFile = fileHandle
        tempFileURL = tempURL
        isRecording = true
        NSLog("Recording started")
    }

    /// Stops the current recording and returns the path to the temporary PCM file.
    ///
    /// The audio engine is stopped, the tap is removed, and the file handle
    /// is closed. The caller is responsible for deleting the temp file after
    /// transcription.
    ///
    /// - Returns: The URL of the recorded PCM audio file.
    /// - Throws: `AudioRecorderError.notRecording` if no recording is in progress.
    func stopRecording() throws -> URL {
        guard isRecording, let engine = audioEngine, let fileHandle = outputFile,
              let fileURL = tempFileURL else {
            throw AudioRecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        fileHandle.closeFile()

        audioEngine = nil
        outputFile = nil
        tempFileURL = nil
        isRecording = false

        NSLog("Recording stopped: \(fileURL.lastPathComponent)")
        return fileURL
    }

    /// Converts an audio buffer to 16kHz mono and writes it to the output file.
    ///
    /// - Parameters:
    ///   - buffer: The captured audio buffer from the engine tap.
    ///   - converter: The format converter (input format -> 16kHz mono).
    ///   - targetFormat: The target AVAudioFormat (16kHz mono Float32).
    ///   - fileHandle: The file handle to write converted samples to.
    private func convertAndWrite(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        fileHandle: FileHandle
    ) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (16000.0 / buffer.format.sampleRate)
        )
        guard frameCapacity > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCapacity
        ) else { return }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            NSLog("Audio conversion error: \(error.localizedDescription)")
            return
        }

        guard let channelData = convertedBuffer.floatChannelData else { return }
        let data = Data(
            bytes: channelData[0],
            count: Int(convertedBuffer.frameLength) * MemoryLayout<Float>.size
        )
        fileHandle.write(data)
    }

    /// Sets the audio input device on the engine via CoreAudio.
    ///
    /// - Parameters:
    ///   - deviceID: The CoreAudio AudioDeviceID to use.
    ///   - engine: The AVAudioEngine whose input node should be configured.
    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) {
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        var deviceIDValue = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDValue,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    deinit {
        if isRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            outputFile?.closeFile()
            if let url = tempFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// Errors specific to audio recording operations.
enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case engineStartFailed(String)
    case formatConversionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is in progress."
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .formatConversionFailed:
            return "Failed to create audio format converter."
        }
    }
}
