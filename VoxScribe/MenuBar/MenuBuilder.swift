import Cocoa

/// Constructs the right-click context menu for the status bar icon.
///
/// The menu includes: audio input source selection, clipboard history,
/// settings, and quit.
enum MenuBuilder {
    /// Builds the complete right-click context menu.
    ///
    /// - Parameters:
    ///   - clipboardHistory: The history manager for displaying past transcriptions.
    ///   - audioDeviceManager: The device manager for listing input devices.
    ///   - settings: The app settings for reading current preferences.
    ///   - modelManager: The model manager for the settings panel.
    ///   - statusBarController: The controller for opening the settings popover.
    /// - Returns: A configured NSMenu ready for display.
    static func buildMenu(
        clipboardHistory: ClipboardHistory,
        audioDeviceManager: AudioDeviceManager,
        settings: AppSettings,
        modelManager: ModelManager,
        statusBarController: StatusBarController
    ) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(buildAudioInputSubmenu(
            audioDeviceManager: audioDeviceManager,
            settings: settings
        ))
        menu.addItem(buildHistorySubmenu(clipboardHistory: clipboardHistory))
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(StatusBarController.openSettings), keyEquivalent: ",")
        settingsItem.target = statusBarController
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit VoxScribe",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return menu
    }

    /// Builds the "Audio Input Source" submenu listing available devices.
    ///
    /// - Parameters:
    ///   - audioDeviceManager: The device manager providing the device list.
    ///   - settings: The settings to check which device is currently selected.
    /// - Returns: An NSMenuItem with a submenu of audio input devices.
    private static func buildAudioInputSubmenu(
        audioDeviceManager: AudioDeviceManager,
        settings: AppSettings
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "Audio Input Source", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let systemDefault = NSMenuItem(title: "System Default", action: nil, keyEquivalent: "")
        systemDefault.state = settings.audioInputDeviceID == nil ? .on : .off
        let defaultHandler = MenuActionHandler {
            settings.audioInputDeviceID = nil
        }
        systemDefault.target = defaultHandler
        systemDefault.action = #selector(MenuActionHandler.handleAction)
        systemDefault.representedObject = defaultHandler
        submenu.addItem(systemDefault)
        submenu.addItem(NSMenuItem.separator())

        for device in audioDeviceManager.inputDevices {
            let deviceItem = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
            deviceItem.state = settings.audioInputDeviceID == device.uid ? .on : .off
            let handler = MenuActionHandler {
                settings.audioInputDeviceID = device.uid
            }
            deviceItem.target = handler
            deviceItem.action = #selector(MenuActionHandler.handleAction)
            deviceItem.representedObject = handler
            submenu.addItem(deviceItem)
        }

        item.submenu = submenu
        return item
    }

    /// Builds the "Clipboard History" submenu with recent transcriptions.
    ///
    /// - Parameter clipboardHistory: The history manager providing entries.
    /// - Returns: An NSMenuItem with a submenu of history entries.
    private static func buildHistorySubmenu(
        clipboardHistory: ClipboardHistory
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if clipboardHistory.entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No history", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for entry in clipboardHistory.entries {
                let title = "\(entry.preview) -- \(entry.relativeTimestamp)"
                let entryItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let handler = MenuActionHandler {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
                entryItem.target = handler
                entryItem.action = #selector(MenuActionHandler.handleAction)
                entryItem.representedObject = handler
                submenu.addItem(entryItem)
            }
        }

        item.submenu = submenu
        return item
    }
}

/// A helper class that holds a closure for NSMenuItem action targeting.
///
/// Stored as the menu item's `representedObject` to prevent deallocation
/// while the menu is visible.
final class MenuActionHandler: NSObject {
    private let closure: () -> Void

    /// Creates a handler wrapping the given closure.
    ///
    /// - Parameter closure: The action to perform when the menu item is clicked.
    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    /// Invoked by the menu item's action mechanism.
    @objc func handleAction() {
        closure()
    }
}
