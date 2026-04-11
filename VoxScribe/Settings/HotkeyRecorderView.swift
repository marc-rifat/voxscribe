import Cocoa
import SwiftUI

/// An NSView-based key recorder that captures a single keystroke
/// (key code + modifiers) for the global hotkey setting.
///
/// When focused, displays "Press a key..." and captures the next
/// keyDown event. The recorded key is displayed as a human-readable
/// string (e.g., "Cmd+Shift+R").
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int?
    @Binding var modifierFlags: UInt?

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onKeyRecorded = { code, flags in
            keyCode = code
            modifierFlags = flags
        }
        view.updateDisplay(keyCode: keyCode, modifierFlags: modifierFlags)
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.updateDisplay(keyCode: keyCode, modifierFlags: modifierFlags)
    }
}

/// The backing NSView that handles keyDown events for hotkey recording.
final class HotkeyRecorderNSView: NSView {
    var onKeyRecorded: ((Int, UInt) -> Void)?
    private let label = NSTextField(labelWithString: "Click to set hotkey")
    private var isListening = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isListening = true
        label.stringValue = "Press a key..."
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func keyDown(with event: NSEvent) {
        guard isListening else {
            super.keyDown(with: event)
            return
        }

        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue

        isListening = false
        layer?.borderColor = NSColor.separatorColor.cgColor
        onKeyRecorded?(keyCode, UInt(modifiers))
        updateDisplay(keyCode: keyCode, modifierFlags: UInt(modifiers))
    }

    /// Updates the label to show the currently configured hotkey.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code, or nil if not set.
    ///   - modifierFlags: The modifier flags, or nil if not set.
    func updateDisplay(keyCode: Int?, modifierFlags: UInt?) {
        guard !isListening else { return }
        guard let keyCode = keyCode else {
            label.stringValue = "Click to set hotkey"
            return
        }

        var parts: [String] = []
        if let flags = modifierFlags {
            let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(flags))
            if nsFlags.contains(.control) { parts.append("Ctrl") }
            if nsFlags.contains(.option) { parts.append("Opt") }
            if nsFlags.contains(.shift) { parts.append("Shift") }
            if nsFlags.contains(.command) { parts.append("Cmd") }
        }

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        label.stringValue = parts.joined(separator: "+")
    }

    /// Converts a virtual key code to a human-readable string.
    ///
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: A display string for the key (e.g., "R", "Space", "F5").
    private func keyCodeToString(_ keyCode: Int) -> String {
        let knownKeys: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 111: "F12", 103: "F11",
            118: "F4", 120: "F2", 122: "F1",
        ]
        return knownKeys[keyCode] ?? "Key(\(keyCode))"
    }
}
