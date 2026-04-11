import ServiceManagement
import SwiftUI

/// The main settings panel presented as a popover from the menu bar.
///
/// Contains sections for hotkey configuration, audio input selection,
/// model management, history settings, and launch-at-login toggle.
struct SettingsView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var audioDeviceManager: AudioDeviceManager
    @ObservedObject var settings: AppSettings
    let clipboardHistory: ClipboardHistory
    let onHotkeyChanged: () -> Void
    var onModelChanged: ((WhisperModel) -> Void)?
    var onModelDeleted: ((WhisperModel) -> Void)?
    var onClose: (() -> Void)?

    @State private var hotkeyKeyCode: Int?
    @State private var hotkeyModifierFlags: UInt?
    @State private var historyLimitText: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var selectedDeviceUID: String?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // Hotkey Section
            GroupBox(label: Text("Global Hotkey")) {
                VStack(alignment: .leading, spacing: 8) {
                    HotkeyRecorderView(
                        keyCode: $hotkeyKeyCode,
                        modifierFlags: $hotkeyModifierFlags
                    )
                    .frame(maxWidth: .infinity)
                    .onChange(of: hotkeyKeyCode) { newValue in
                        settings.hotkeyKeyCode = newValue
                        onHotkeyChanged()
                    }
                    .onChange(of: hotkeyModifierFlags) { newValue in
                        settings.hotkeyModifierFlags = newValue
                        onHotkeyChanged()
                    }
                }
                .padding(4)
            }

            // Audio Input Section
            GroupBox(label: Text("Audio Input")) {
                Picker("Input Device", selection: $selectedDeviceUID) {
                    Text("System Default").tag(nil as String?)
                    ForEach(audioDeviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                .onChange(of: selectedDeviceUID) { newValue in
                    settings.audioInputDeviceID = newValue
                }
                .padding(4)
            }

            // Model Management Section
            GroupBox(label: Text("Whisper Models")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(WhisperModel.allModels) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name)
                                    .font(.system(.body, design: .monospaced))
                                Text("\(model.isEnglishOnly ? "English" : "Multilingual") - \(model.displaySize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            if let progress = modelManager.activeDownloads[model.name] {
                                ProgressView(value: progress)
                                    .frame(width: 80)
                                Text("\(Int(progress * 100))%")
                                    .font(.caption)
                                    .frame(width: 35)
                            } else if modelManager.isModelDownloaded(model) {
                                if settings.selectedModelName == model.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Button(action: {
                                        settings.selectedModelName = model.name
                                        onModelChanged?(model)
                                    }) {
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Use this model")
                                }
                                Button(action: {
                                    try? modelManager.deleteModel(model)
                                    onModelDeleted?(model)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Delete this model")
                            } else {
                                Button(action: {
                                    modelManager.downloadModel(model) { result in
                                        switch result {
                                        case .success:
                                            // Auto-select if no model is currently active
                                            if settings.selectedModelName.isEmpty ||
                                               !modelManager.isModelDownloaded(
                                                   WhisperModel.allModels.first { $0.name == settings.selectedModelName } ??
                                                   model
                                               ) {
                                                settings.selectedModelName = model.name
                                                onModelChanged?(model)
                                            }
                                        case .failure(let error):
                                            NSLog("Download failed: \(error.localizedDescription)")
                                        }
                                    }
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Download this model")
                            }
                        }
                        if model.id != WhisperModel.allModels.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(4)
            }

            // History Section
            GroupBox(label: Text("Clipboard History")) {
                HStack {
                    Text("Max entries:")
                    TextField("50", text: $historyLimitText)
                        .frame(width: 60)
                        .onSubmit {
                            if let value = Int(historyLimitText), value > 0 {
                                settings.historyLimit = value
                            }
                        }
                    Spacer()
                    Button(action: { clipboardHistory.clear() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all history")
                }
                .padding(4)
            }

            // Launch at Login
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    settings.launchAtLogin = newValue
                    if newValue {
                        do {
                            try SMAppService.mainApp.register()
                            NSLog("Launch at login: registered successfully")
                        } catch {
                            NSLog("Launch at login: registration failed - \(error.localizedDescription)")
                        }
                    } else {
                        do {
                            try SMAppService.mainApp.unregister()
                            NSLog("Launch at login: unregistered successfully")
                        } catch {
                            NSLog("Launch at login: unregistration failed - \(error.localizedDescription)")
                        }
                    }
                }
        }
        .padding()
        }
        .frame(width: 380, height: 500)
        .onAppear {
            hotkeyKeyCode = settings.hotkeyKeyCode
            hotkeyModifierFlags = settings.hotkeyModifierFlags
            historyLimitText = "\(settings.historyLimit)"
            launchAtLogin = settings.launchAtLogin
            selectedDeviceUID = settings.audioInputDeviceID
        }
    }
}
