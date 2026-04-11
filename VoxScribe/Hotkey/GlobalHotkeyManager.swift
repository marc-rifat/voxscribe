import Cocoa
import Foundation

/// Manages a global keyboard shortcut that works even when the app is not focused.
///
/// Uses a `CGEvent` tap to intercept key events system-wide. The hotkey
/// is configurable via a key code and modifier flags stored in `AppSettings`.
///
/// - Important: Requires Accessibility permissions in System Settings.
final class GlobalHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let settings: AppSettings
    private var handler: (() -> Void)?

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
    /// - Returns: `true` if the event tap was created successfully,
    ///   `false` if accessibility permissions are missing.
    @discardableResult
    func register(handler: @escaping () -> Void) -> Bool {
        self.handler = handler
        unregister()

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: globalHotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Failed to create event tap. Check Accessibility permissions.")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Global hotkey registered")
        return true
    }

    /// Removes the global hotkey listener and cleans up resources.
    func unregister() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Checks whether the given key event matches the configured hotkey.
    ///
    /// - Parameter event: The CGEvent to check.
    /// - Returns: `true` if the event's key code and modifiers match the settings.
    fileprivate func matchesHotkey(_ event: CGEvent) -> Bool {
        guard let keyCode = settings.hotkeyKeyCode,
              let modifierFlags = settings.hotkeyModifierFlags else {
            return false
        }

        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = event.flags.rawValue & (
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskShift.rawValue |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskControl.rawValue
        )

        return eventKeyCode == keyCode && eventModifiers == UInt64(modifierFlags)
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

/// C-function callback for the CGEvent tap. Forwards matching hotkey events
/// to the GlobalHotkeyManager instance.
private func globalHotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown,
          let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if manager.matchesHotkey(event) {
        manager.fireHandler()
        return nil  // consume the event
    }

    return Unmanaged.passRetained(event)
}
