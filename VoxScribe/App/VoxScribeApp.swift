import Cocoa

/// Application delegate for VoxScribe.
///
/// Serves as the entry point for the macOS menu bar application.
/// VoxScribe runs as a background-only app (LSUIElement = true),
/// meaning it has no Dock icon or main window -- only a menu bar item.
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Called after the application has finished launching.
    ///
    /// Use this method to initialize application state, set up the
    /// menu bar status item, and configure any services that need to
    /// be ready before the user interacts with the app.
    ///
    /// - Parameter notification: The notification that the app has launched.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("VoxScribe launched")
    }

    /// Called just before the application terminates.
    ///
    /// Use this method to perform any necessary cleanup -- stopping
    /// active recordings, releasing audio resources, and persisting state.
    ///
    /// - Parameter notification: The notification that the app will terminate.
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("VoxScribe terminating")
    }
}
