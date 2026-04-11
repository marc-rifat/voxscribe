import ServiceManagement
import SwiftUI

/// A unified menu bar panel that combines all controls into a single
/// dropdown, styled like a native macOS Control Center panel.
///
/// Displayed on right-click of the status bar icon. Contains sections
/// for model status, hotkey, audio input, models, clipboard history,
/// and app controls -- all in one view.
struct MenuBarPanelView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var audioDeviceManager: AudioDeviceManager
    @ObservedObject var settings: AppSettings
    let clipboardHistory: ClipboardHistory
    let onHotkeyChanged: () -> Void
    var onModelChanged: ((WhisperModel) -> Void)?
    var onModelDeleted: ((WhisperModel) -> Void)?
    var onQuit: (() -> Void)?

    @State private var hotkeyKeyCode: Int?
    @State private var hotkeyModifierFlags: UInt?
    @State private var historyLimitText: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var selectedDeviceUID: String?
    @State private var showModels: Bool = false
    @State private var showHistory: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {

                // Active Model Status
                sectionHeader("Active Model")
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                        .frame(width: 20)
                    Text(settings.selectedModelName)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    if let model = WhisperModel.allModels.first(where: { $0.name == settings.selectedModelName }) {
                        Text(model.isEnglishOnly ? "EN" : "Multi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                panelDivider()

                // Hotkey
                sectionHeader("Hotkey")
                HotkeyRecorderView(
                    keyCode: $hotkeyKeyCode,
                    modifierFlags: $hotkeyModifierFlags
                )
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .padding(.horizontal, 12)
                .onChange(of: hotkeyKeyCode) { newValue in
                    settings.hotkeyKeyCode = newValue
                    onHotkeyChanged()
                }
                .onChange(of: hotkeyModifierFlags) { newValue in
                    settings.hotkeyModifierFlags = newValue
                    onHotkeyChanged()
                }

                panelDivider()

                // Audio Input
                sectionHeader("Input")
                Picker("", selection: $selectedDeviceUID) {
                    Text("System Default").tag(nil as String?)
                    ForEach(audioDeviceManager.inputDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                .labelsHidden()
                .padding(.horizontal, 12)
                .onChange(of: selectedDeviceUID) { newValue in
                    settings.audioInputDeviceID = newValue
                }

                panelDivider()

                // Models (collapsible)
                panelButton(
                    icon: "cube.box",
                    label: "Models",
                    trailing: Image(systemName: showModels ? "chevron.up" : "chevron.down")
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showModels.toggle()
                    }
                }

                if showModels {
                    VStack(spacing: 0) {
                        ForEach(WhisperModel.allModels) { model in
                            modelRow(model)
                            if model.id != WhisperModel.allModels.last?.id {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                panelDivider()

                // Clipboard History (collapsible)
                panelButton(
                    icon: "clipboard",
                    label: "History (\(clipboardHistory.entries.count))",
                    trailing: Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHistory.toggle()
                    }
                }

                if showHistory {
                    VStack(spacing: 0) {
                        if clipboardHistory.entries.isEmpty {
                            Text("No history")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(clipboardHistory.entries) { entry in
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.text, forType: .string)
                                }) {
                                    HStack {
                                        Text(entry.preview)
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(entry.relativeTimestamp)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // History controls
                        HStack {
                            Text("Max:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("50", text: $historyLimitText)
                                .font(.caption)
                                .frame(width: 40)
                                .onSubmit {
                                    if let value = Int(historyLimitText), value > 0 {
                                        settings.historyLimit = value
                                    }
                                }
                            Spacer()
                            Button(action: { clipboardHistory.clear() }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }

                panelDivider()

                // Launch at Login
                HStack {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: launchAtLogin) { newValue in
                            settings.launchAtLogin = newValue
                            if newValue {
                                do {
                                    try SMAppService.mainApp.register()
                                    NSLog("Launch at login: registered")
                                } catch {
                                    NSLog("Launch at login: failed - \(error.localizedDescription)")
                                }
                            } else {
                                do {
                                    try SMAppService.mainApp.unregister()
                                    NSLog("Launch at login: unregistered")
                                } catch {
                                    NSLog("Launch at login: failed - \(error.localizedDescription)")
                                }
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                panelDivider()

                // Quit
                panelButton(icon: "xmark.circle", label: "Quit VoxScribe", color: .red) {
                    onQuit?()
                }

                Spacer().frame(height: 4)
            }
        }
        .frame(width: 320)
        .onAppear {
            hotkeyKeyCode = settings.hotkeyKeyCode
            hotkeyModifierFlags = settings.hotkeyModifierFlags
            historyLimitText = "\(settings.historyLimit)"
            launchAtLogin = settings.launchAtLogin
            selectedDeviceUID = settings.audioInputDeviceID
        }
    }

    // MARK: - Components

    /// Section header label.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    /// A thin divider line.
    @ViewBuilder
    private func panelDivider() -> some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    /// A clickable row with icon and label, styled like a menu item.
    private func panelButton(
        icon: String,
        label: String,
        color: Color = .primary,
        trailing: Image? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .foregroundColor(color)
                Spacer()
                if let trailing = trailing {
                    trailing
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A single model row with download/use/delete controls.
    private func modelRow(_ model: WhisperModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(.caption, design: .monospaced))
                Text("\(model.isEnglishOnly ? "English" : "Multilingual") - \(model.displaySize)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()

            if let progress = modelManager.activeDownloads[model.name] {
                ProgressView(value: progress)
                    .frame(width: 50)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 9))
                    .frame(width: 28)
            } else if modelManager.isModelDownloaded(model) {
                if settings.selectedModelName == model.name {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button(action: {
                        settings.selectedModelName = model.name
                        onModelChanged?(model)
                    }) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: {
                    try? modelManager.deleteModel(model)
                    onModelDeleted?(model)
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    modelManager.downloadModel(model) { result in
                        if case .success = result {
                            if !modelManager.isModelDownloaded(
                                WhisperModel.allModels.first { $0.name == settings.selectedModelName } ?? model
                            ) {
                                settings.selectedModelName = model.name
                                onModelChanged?(model)
                            }
                        }
                    }
                }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
