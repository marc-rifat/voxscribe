import Cocoa
import UserNotifications

/// The three states the menu bar icon can be in.
enum AppState {
    case idle
    case recording
    case transcribing
}

/// Manages the NSStatusItem in the menu bar, handling left-click toggle
/// and right-click context menu, icon state animations, and coordinating
/// the recording-transcription-clipboard pipeline.
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let audioRecorder: AudioRecorder
    private let transcriptionEngine: TranscriptionEngine
    private let clipboardHistory: ClipboardHistory
    private let settings: AppSettings
    private let modelManager: ModelManager
    private let audioDeviceManager: AudioDeviceManager

    private var animationTimer: Timer?
    private(set) var appState: AppState = .idle

    /// Creates a StatusBarController and sets up the menu bar icon.
    ///
    /// - Parameters:
    ///   - audioRecorder: The recorder for capturing audio.
    ///   - transcriptionEngine: The whisper.cpp wrapper for transcription.
    ///   - clipboardHistory: The history manager for storing transcriptions.
    ///   - settings: The app settings instance.
    ///   - modelManager: The model download/delete manager.
    ///   - audioDeviceManager: The audio input device enumerator.
    init(
        audioRecorder: AudioRecorder,
        transcriptionEngine: TranscriptionEngine,
        clipboardHistory: ClipboardHistory,
        settings: AppSettings,
        modelManager: ModelManager,
        audioDeviceManager: AudioDeviceManager
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionEngine = transcriptionEngine
        self.clipboardHistory = clipboardHistory
        self.settings = settings
        self.modelManager = modelManager
        self.audioDeviceManager = audioDeviceManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        updateIcon()
    }

    /// Configures the status bar button with click event handling.
    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Routes left clicks to toggle recording and right clicks to the context menu.
    ///
    /// - Parameter sender: The NSStatusBarButton that was clicked.
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleRecording()
        }
    }

    /// Toggles between recording and idle states. Called by both left-click
    /// and the global hotkey.
    func toggleRecording() {
        switch appState {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            break  // ignore clicks during transcription
        }
    }

    /// Starts audio recording and transitions the icon to the recording state.
    private func startRecording() {
        if let deviceUID = settings.audioInputDeviceID {
            let device = audioDeviceManager.inputDevices.first { $0.uid == deviceUID }
            audioRecorder.inputDeviceID = device?.id
        } else {
            audioRecorder.inputDeviceID = nil
        }

        do {
            try audioRecorder.startRecording()
            appState = .recording
            updateIcon()
            startRecordingAnimation()
        } catch {
            NSLog("Failed to start recording: \(error.localizedDescription)")
            sendNotification(title: "Recording Failed", body: error.localizedDescription)
        }
    }

    /// Stops recording, transitions to transcribing state, and starts transcription.
    private func stopRecordingAndTranscribe() {
        do {
            let audioURL = try audioRecorder.stopRecording()
            appState = .transcribing
            updateIcon()
            startTranscribingAnimation()

            transcriptionEngine.transcribe(audioFileURL: audioURL) { [weak self] result in
                self?.stopAnimation()
                switch result {
                case .success(let text):
                    self?.handleTranscriptionResult(text)
                case .failure(let error):
                    NSLog("Transcription failed: \(error.localizedDescription)")
                    self?.sendNotification(
                        title: "Transcription Failed",
                        body: error.localizedDescription
                    )
                }
                try? FileManager.default.removeItem(at: audioURL)
                self?.appState = .idle
                self?.updateIcon()
            }
        } catch {
            NSLog("Failed to stop recording: \(error.localizedDescription)")
            appState = .idle
            updateIcon()
        }
    }

    /// Copies transcription text to the clipboard, saves to history,
    /// and shows a notification.
    ///
    /// - Parameter text: The transcribed text.
    private func handleTranscriptionResult(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        clipboardHistory.addEntry(text: text)
        sendNotification(title: "VoxScribe", body: "Copied to clipboard")
    }

    /// Updates the menu bar icon based on the current app state.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        switch appState {
        case .idle:
            button.image = NSImage(
                systemSymbolName: "mic",
                accessibilityDescription: "VoxScribe - idle"
            )
        case .recording:
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "VoxScribe - recording"
            )
        case .transcribing:
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "VoxScribe - transcribing"
            )
        }
    }

    /// Starts the pulsing red animation for the recording state.
    private func startRecordingAnimation() {
        stopAnimation()
        var isRed = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            if isRed {
                button.image = NSImage(
                    systemSymbolName: "mic.fill",
                    accessibilityDescription: "VoxScribe - recording"
                )
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
            isRed.toggle()
        }
    }

    /// Starts the pulsing animation for the transcribing state.
    private func startTranscribingAnimation() {
        stopAnimation()
        var isHighlighted = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            button.contentTintColor = isHighlighted ? .systemOrange : nil
            isHighlighted.toggle()
        }
    }

    /// Stops any running icon animation and resets the tint color.
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        statusItem.button?.contentTintColor = nil
    }

    /// Sends a macOS user notification.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Builds and displays the right-click context menu.
    private func showContextMenu() {
        let menu = MenuBuilder.buildMenu(
            clipboardHistory: clipboardHistory,
            audioDeviceManager: audioDeviceManager,
            settings: settings,
            modelManager: modelManager,
            statusBarController: self
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // reset so left click works again
    }
}
