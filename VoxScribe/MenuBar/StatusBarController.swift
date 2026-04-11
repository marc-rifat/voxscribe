import Cocoa
import SwiftUI
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
    weak var hotkeyManager: GlobalHotkeyManager?

    private var animationTimer: Timer?
    private var settingsPanel: NSPopover?
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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        updateIcon()
        NSLog("StatusBarController initialized, button: \(String(describing: statusItem.button)), image: \(String(describing: statusItem.button?.image)), title: \(String(describing: statusItem.button?.title))")
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
            NSLog("Recording STARTED")
        } catch {
            NSLog("Failed to start recording: \(error.localizedDescription)")
            sendNotification(title: "Recording Failed", body: error.localizedDescription)
        }
    }

    /// Stops recording, transitions to transcribing state, and starts transcription.
    private func stopRecordingAndTranscribe() {
        do {
            let audioURL = try audioRecorder.stopRecording()
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
            NSLog("Recording STOPPED. File: \(audioURL.lastPathComponent), size: \(fileSize) bytes")
            appState = .transcribing
            updateIcon()
            startTranscribingAnimation()

            NSLog("Starting transcription...")
            transcriptionEngine.transcribe(audioFileURL: audioURL) { [weak self] result in
                self?.stopAnimation()
                switch result {
                case .success(let text):
                    NSLog("Transcription SUCCESS: '\(text)'")
                    self?.handleTranscriptionResult(text)
                case .failure(let error):
                    NSLog("Transcription FAILED: \(error.localizedDescription)")
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

    /// Creates a colored non-template menu bar icon from an SF Symbol.
    ///
    /// macOS forces template rendering for menu bar icons, so this renders
    /// the symbol into a bitmap with the desired color and marks it non-template.
    ///
    /// - Parameters:
    ///   - symbolName: The SF Symbol name.
    ///   - color: The tint color.
    /// - Returns: A non-template NSImage rendered in the given color.
    private func coloredIcon(_ symbolName: String, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        let image = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Updates the menu bar icon based on the current app state.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        switch appState {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoxScribe")
        case .recording:
            button.image = coloredIcon("mic.fill", color: .systemRed)
        case .transcribing:
            button.image = coloredIcon("waveform", color: .systemGreen)
        }
    }

    /// Animates the menu bar icon during transcription by cycling through
    /// waveform symbols in orange.
    private func startTranscribingAnimation() {
        stopAnimation()
        let icons = ["waveform.path.ecg", "waveform", "waveform.path"]
        var index = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            button.image = self?.coloredIcon(icons[index % icons.count], color: .systemGreen)
            index += 1
        }
    }

    /// Stops any running icon animation.
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
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

    /// Opens the settings popover attached to the menu bar icon.
    @objc func openSettings() {
        if let existing = settingsPanel, existing.isShown {
            existing.performClose(nil)
            settingsPanel = nil
            return
        }

        guard let button = statusItem.button else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: SettingsView(
                modelManager: modelManager,
                audioDeviceManager: audioDeviceManager,
                settings: settings,
                clipboardHistory: clipboardHistory,
                onHotkeyChanged: { [weak self] in
                    guard let self = self else { return }
                    self.hotkeyManager?.unregister()
                    self.hotkeyManager?.register { [weak self] in
                        self?.toggleRecording()
                    }
                },
                onModelChanged: { [weak self] model in
                    guard let self = self else { return }
                    NSLog("Switching to model: \(model.name)")
                    self.transcriptionEngine.loadModel(model) { result in
                        switch result {
                        case .success:
                            NSLog("Model switched to: \(model.name)")
                        case .failure(let error):
                            NSLog("Failed to switch model: \(error.localizedDescription)")
                        }
                    }
                },
                onModelDeleted: { [weak self] model in
                    guard let self = self else { return }
                    // If the deleted model was the active one, unload it
                    if self.transcriptionEngine.loadedModelName == model.name {
                        NSLog("Active model '\(model.name)' was deleted, unloading")
                        self.transcriptionEngine.unloadModel()
                        // Try to fall back to another downloaded model
                        if let fallback = self.modelManager.smallestDownloadedModel() {
                            self.settings.selectedModelName = fallback.name
                            self.transcriptionEngine.loadModel(fallback) { result in
                                if case .success = result {
                                    NSLog("Fell back to model: \(fallback.name)")
                                }
                            }
                        }
                    }
                },
                onClose: { [weak self] in
                    self?.settingsPanel?.performClose(nil)
                    self?.settingsPanel = nil
                }
            )
        )
        settingsPanel = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
        guard let button = statusItem.button else { return }
        let location = NSPoint(x: 0, y: button.bounds.height + 5)
        menu.popUp(positioning: nil, at: location, in: button)
    }
}
