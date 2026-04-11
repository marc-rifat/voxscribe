import Cocoa
import Carbon

/// Manages a global keyboard shortcut that works even when the app is not focused.
///
/// Uses Carbon's `RegisterEventHotKey` API for reliable system-wide hotkey
/// detection that works with all modifier combinations including Cmd+Delete.
///
/// - Important: Requires Accessibility permissions in System Settings.
final class GlobalHotkeyManager {
    private let settings: AppSettings
    private var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Creates a GlobalHotkeyManager.
    ///
    /// - Parameter settings: The AppSettings instance to read hotkey configuration from.
    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Registers the global hotkey and begins listening for key events.
    ///
    /// When the configured hotkey is pressed, the provided handler closure
    /// is called on the main thread.
    ///
    /// - Parameter handler: The closure to invoke when the hotkey is pressed.
    /// - Returns: `true` if the hotkey was registered successfully.
    @discardableResult
    func register(handler: @escaping () -> Void) -> Bool {
        self.handler = handler
        unregister()

        guard let keyCode = settings.hotkeyKeyCode else {
            NSLog("Global hotkey: no key code configured")
            return false
        }

        let modifierFlags = settings.hotkeyModifierFlags ?? 0
        let carbonModifiers = carbonModifierFlags(from: modifierFlags)

        // Install event handler for hotkey events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.fireHandler()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        guard status == noErr else {
            NSLog("Global hotkey: failed to install event handler (status: \(status))")
            return false
        }

        // Register the hotkey
        let hotKeyID = EventHotKeyID(signature: OSType(0x564F5853), id: 1) // "VOXS"
        var hotKeyIDVar = hotKeyID

        let regStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyIDVar,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard regStatus == noErr else {
            NSLog("Global hotkey: failed to register hotkey (status: \(regStatus))")
            return false
        }

        NSLog("Global hotkey registered (keyCode: \(keyCode), modifiers: \(carbonModifiers))")
        return true
    }

    /// Removes the global hotkey listener and cleans up resources.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    /// Converts NSEvent modifier flags to Carbon modifier flags.
    ///
    /// - Parameter flags: The NSEvent modifier flags as a raw UInt value.
    /// - Returns: The equivalent Carbon modifier flags.
    private func carbonModifierFlags(from flags: UInt) -> UInt32 {
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(flags))
        var carbon: UInt32 = 0
        if nsFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if nsFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if nsFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if nsFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// Invokes the registered handler on the main thread.
    fileprivate func fireHandler() {
        DispatchQueue.main.async { [weak self] in
            self?.handler?()
        }
    }

    deinit {
        unregister()
    }
}
