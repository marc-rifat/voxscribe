import Cocoa
import ServiceManagement
import UserNotifications

/// The main application delegate that initializes and wires all components.
///
/// Sets up the transcription engine, audio recorder, clipboard history,
/// model manager, settings, hotkey manager, and status bar controller.
/// Manages the app lifecycle including model loading on launch and
/// cleanup on termination.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: GlobalHotkeyManager?
    private var transcriptionEngine: TranscriptionEngine?
    private var settings: AppSettings?
    private var modelManager: ModelManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationPermission()

        let settings = AppSettings()
        let modelManager = ModelManager()
        let audioRecorder = AudioRecorder()
        let audioDeviceManager = AudioDeviceManager()
        let transcriptionEngine = TranscriptionEngine()

        let historyFileURL = WhisperModel.storageDirectory
            .appendingPathComponent("history.json")
        let clipboardHistory = ClipboardHistory(
            fileURL: historyFileURL,
            limit: settings.historyLimit
        )

        // Load the selected model, falling back to the smallest available
        loadInitialModel(
            transcriptionEngine: transcriptionEngine,
            modelManager: modelManager,
            settings: settings
        )

        let statusBarController = StatusBarController(
            audioRecorder: audioRecorder,
            transcriptionEngine: transcriptionEngine,
            clipboardHistory: clipboardHistory,
            settings: settings,
            modelManager: modelManager,
            audioDeviceManager: audioDeviceManager
        )

        let hotkeyManager = GlobalHotkeyManager(settings: settings)
        hotkeyManager.register { [weak statusBarController] in
            statusBarController?.toggleRecording()
        }

        // Configure launch at login
        if settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        }

        statusBarController.hotkeyManager = hotkeyManager
        self.statusBarController = statusBarController
        self.hotkeyManager = hotkeyManager
        self.transcriptionEngine = transcriptionEngine
        self.settings = settings
        self.modelManager = modelManager

        NSLog("VoxScribe launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
        transcriptionEngine?.unloadModel()
        NSLog("VoxScribe terminated")
    }

    /// Loads the user's selected whisper model, with fallback to the smallest
    /// available model if the selected one is missing.
    ///
    /// - Parameters:
    ///   - transcriptionEngine: The engine to load the model into.
    ///   - modelManager: The manager to query for downloaded models.
    ///   - settings: The settings to read/update the selected model name.
    private func loadInitialModel(
        transcriptionEngine: TranscriptionEngine,
        modelManager: ModelManager,
        settings: AppSettings
    ) {
        let selectedModel = WhisperModel.allModels.first {
            $0.name == settings.selectedModelName
        }

        if let model = selectedModel, modelManager.isModelDownloaded(model) {
            do {
                try transcriptionEngine.loadModel(model)
                return
            } catch {
                NSLog("Failed to load selected model: \(error.localizedDescription)")
            }
        }

        // Fallback to smallest downloaded model
        if let fallback = modelManager.smallestDownloadedModel() {
            settings.selectedModelName = fallback.name
            do {
                try transcriptionEngine.loadModel(fallback)
                NSLog("Fell back to model: \(fallback.name)")
            } catch {
                NSLog("Failed to load fallback model: \(error.localizedDescription)")
            }
        } else {
            NSLog("No whisper models downloaded. User must download one from Settings.")
        }
    }

    /// Requests permission to display macOS notifications.
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error = error {
                NSLog("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
}
