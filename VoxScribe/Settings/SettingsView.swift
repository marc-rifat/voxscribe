import ServiceManagement
import SwiftUI

/// The main settings panel presented as a popover from the menu bar.
///
/// Contains sections for hotkey configuration, audio input selection,
/// model management, history settings, and launch-at-login toggle.
struct SettingsView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var audioDeviceManager: AudioDeviceManager
    let settings: AppSettings
    let onHotkeyChanged: () -> Void

    @State private var hotkeyKeyCode: Int?
    @State private var hotkeyModifierFlags: UInt?
    @State private var historyLimitText: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var selectedDeviceUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VoxScribe Settings")
                .font(.headline)

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
                                    Text("Active")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Button("Use") {
                                        settings.selectedModelName = model.name
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Button("Delete") {
                                    try? modelManager.deleteModel(model)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                            } else {
                                Button("Download") {
                                    modelManager.downloadModel(model) { result in
                                        if case .failure(let error) = result {
                                            NSLog("Download failed: \(error.localizedDescription)")
                                        }
                                    }
                                }
                                .buttonStyle(.borderless)
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
                    Button("Clear All") {
                        // This will be connected to the clipboard history instance
                    }
                    .foregroundColor(.red)
                }
                .padding(4)
            }

            // Launch at Login
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    settings.launchAtLogin = newValue
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            hotkeyKeyCode = settings.hotkeyKeyCode
            hotkeyModifierFlags = settings.hotkeyModifierFlags
            historyLimitText = "\(settings.historyLimit)"
            launchAtLogin = settings.launchAtLogin
            selectedDeviceUID = settings.audioInputDeviceID
        }
    }
}
