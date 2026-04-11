import Combine
import Foundation

/// Manages all user-configurable settings via UserDefaults.
///
/// Provides typed access to persisted preferences including hotkey
/// configuration, model selection, audio input device, history limit,
/// and launch-at-login state. Conforms to ObservableObject so SwiftUI
/// views update when settings change.
///
/// - Parameter defaults: The UserDefaults suite to use. Defaults to `.standard`.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    /// Registers default values for all settings keys.
    private func registerDefaults() {
        defaults.register(defaults: [
            "historyLimit": 50,
            "selectedModelName": "tiny",
            "launchAtLogin": false
        ])
    }

    /// The maximum number of transcription history entries to retain.
    var historyLimit: Int {
        get { defaults.integer(forKey: "historyLimit") }
        set { defaults.set(newValue, forKey: "historyLimit") }
    }

    /// Whether the app should launch automatically at login.
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    /// The filename of the currently selected whisper model (e.g., "tiny", "base.en").
    var selectedModelName: String {
        get { defaults.string(forKey: "selectedModelName") ?? "tiny" }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "selectedModelName")
        }
    }

    /// The CoreAudio device ID string for the selected audio input, or nil for system default.
    var audioInputDeviceID: String? {
        get { defaults.string(forKey: "audioInputDeviceID") }
        set { defaults.set(newValue, forKey: "audioInputDeviceID") }
    }

    /// The virtual key code for the global toggle hotkey, or nil if not configured.
    var hotkeyKeyCode: Int? {
        get {
            let value = defaults.integer(forKey: "hotkeyKeyCode")
            return defaults.object(forKey: "hotkeyKeyCode") != nil ? value : nil
        }
        set {
            if let newValue = newValue {
                defaults.set(newValue, forKey: "hotkeyKeyCode")
            } else {
                defaults.removeObject(forKey: "hotkeyKeyCode")
            }
        }
    }

    /// The modifier flags (as raw UInt) for the global toggle hotkey.
    var hotkeyModifierFlags: UInt? {
        get {
            guard defaults.object(forKey: "hotkeyModifierFlags") != nil else { return nil }
            return UInt(defaults.integer(forKey: "hotkeyModifierFlags"))
        }
        set {
            if let newValue = newValue {
                defaults.set(Int(newValue), forKey: "hotkeyModifierFlags")
            } else {
                defaults.removeObject(forKey: "hotkeyModifierFlags")
            }
        }
    }
}
