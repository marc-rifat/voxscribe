# VoxScribe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar-only voice-to-text transcription app that uses whisper.cpp for local, offline transcription and copies results to the clipboard.

**Architecture:** Pure Swift app with `NSStatusItem` for menu bar presence, `AVAudioEngine` for audio capture, and whisper.cpp compiled directly via a C bridging header. Settings in `UserDefaults`, clipboard history persisted as JSON to `~/Documents/VoxScribe Models/history.json`.

**Tech Stack:** Swift, SwiftUI, AppKit, AVAudioEngine, CoreAudio, whisper.cpp (C API), XCTest

---

## File Structure

```
VoxScribe/
├── VoxScribe.xcodeproj/
├── VoxScribe/
│   ├── App/
│   │   ├── VoxScribeApp.swift                 -- @main entry, AppDelegate, app lifecycle
│   │   └── Info.plist                         -- LSUIElement=true, microphone usage
│   ├── MenuBar/
│   │   ├── StatusBarController.swift          -- NSStatusItem, icon states, click handling
│   │   └── MenuBuilder.swift                  -- Right-click NSMenu construction
│   ├── Recording/
│   │   ├── AudioRecorder.swift                -- AVAudioEngine wrapper, record to temp PCM
│   │   └── AudioDeviceManager.swift           -- Enumerate/select CoreAudio input devices
│   ├── Transcription/
│   │   ├── TranscriptionEngine.swift          -- Swift wrapper over whisper.cpp C API
│   │   └── VoxScribe-Bridging-Header.h        -- C bridging header for whisper.h
│   ├── Models/
│   │   ├── ModelManager.swift                 -- Download, delete, list whisper models
│   │   └── WhisperModel.swift                 -- Model metadata enum/struct
│   ├── History/
│   │   ├── ClipboardHistory.swift             -- History storage, pruning, persistence
│   │   └── HistoryEntry.swift                 -- Codable entry (text, timestamp)
│   ├── Settings/
│   │   ├── SettingsView.swift                 -- SwiftUI settings popover (all sections)
│   │   ├── HotkeyRecorderView.swift           -- NSView-based key recorder
│   │   └── AppSettings.swift                  -- UserDefaults property wrappers
│   ├── Hotkey/
│   │   └── GlobalHotkeyManager.swift          -- CGEvent tap for global hotkey
│   ├── Resources/
│   │   └── Assets.xcassets                    -- App icon assets
│   └── VoxScribe.entitlements                 -- Audio input, network, user notifications
├── VoxScribeTests/
│   ├── AppSettingsTests.swift
│   ├── HistoryEntryTests.swift
│   ├── ClipboardHistoryTests.swift
│   ├── WhisperModelTests.swift
│   └── ModelManagerTests.swift
└── libs/
    └── whisper.cpp/                           -- git submodule
```

---

## Task 1: Xcode Project Scaffold + whisper.cpp Integration

**Files:**
- Create: `VoxScribe.xcodeproj/` (via `swift package init` + Xcode project generation)
- Create: `VoxScribe/App/VoxScribeApp.swift`
- Create: `VoxScribe/App/Info.plist`
- Create: `VoxScribe/VoxScribe.entitlements`
- Create: `VoxScribe/Transcription/VoxScribe-Bridging-Header.h`
- Create: `libs/whisper.cpp/` (git submodule)

- [ ] **Step 1: Create the Xcode project**

Open Xcode and create a new macOS App project:
- Product Name: `VoxScribe`
- Team: (your Apple Developer account)
- Organization Identifier: `com.voxscribe`
- Interface: SwiftUI
- Language: Swift
- Uncheck "Include Tests" (we will add the test target manually for better control)

Save into `/Users/marc/Projects/voxscribe/`.

Alternatively, from the command line:

```bash
cd /Users/marc/Projects/voxscribe
mkdir -p VoxScribe VoxScribeTests libs
```

- [ ] **Step 2: Configure Info.plist for menu bar-only app**

Edit `VoxScribe/App/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoxScribe needs microphone access to record audio for transcription.</string>
    <key>CFBundleName</key>
    <string>VoxScribe</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
</dict>
</plist>
```

- [ ] **Step 3: Configure entitlements**

Create `VoxScribe/VoxScribe.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Add whisper.cpp as a git submodule**

```bash
cd /Users/marc/Projects/voxscribe
git submodule add https://github.com/ggerganov/whisper.cpp.git libs/whisper.cpp
```

- [ ] **Step 5: Create the C bridging header**

Create `VoxScribe/Transcription/VoxScribe-Bridging-Header.h`:

```c
#ifndef VoxScribe_Bridging_Header_h
#define VoxScribe_Bridging_Header_h

#include "whisper.h"

#endif
```

In Xcode, set the bridging header path in Build Settings:
- `Swift Compiler - General` > `Objective-C Bridging Header` = `VoxScribe/Transcription/VoxScribe-Bridging-Header.h`

Add the whisper.cpp source files to the Xcode project:
- Add `libs/whisper.cpp/whisper.cpp` and `libs/whisper.cpp/whisper.h` to the project
- Add `libs/whisper.cpp/ggml/src/ggml.c` and related ggml source files
- Set Header Search Paths to include `libs/whisper.cpp` and `libs/whisper.cpp/ggml/include`

- [ ] **Step 6: Create a minimal app entry point**

Create `VoxScribe/App/VoxScribeApp.swift`:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("VoxScribe launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("VoxScribe terminating")
    }
}
```

- [ ] **Step 7: Build and verify**

Run: `Cmd+B` in Xcode
Expected: Project compiles successfully with no errors. whisper.cpp symbols are available via the bridging header.

- [ ] **Step 8: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/ VoxScribeTests/ libs/ .gitmodules VoxScribe.xcodeproj/
git commit -m "chore: scaffold Xcode project with whisper.cpp submodule

Set up macOS menu bar app (LSUIElement=true), configure entitlements
for audio input and network access, add whisper.cpp as a git submodule,
and create the C bridging header for Swift interop."
```

---

## Task 2: AppSettings (UserDefaults Wrapper)

**Files:**
- Create: `VoxScribe/Settings/AppSettings.swift`
- Create: `VoxScribeTests/AppSettingsTests.swift`

- [ ] **Step 1: Write failing tests for AppSettings**

Create `VoxScribeTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import VoxScribe

final class AppSettingsTests: XCTestCase {
    private var settings: AppSettings!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.voxscribe.tests")!
        defaults.removePersistentDomain(forName: "com.voxscribe.tests")
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "com.voxscribe.tests")
        super.tearDown()
    }

    func testDefaultHistoryLimit() {
        XCTAssertEqual(settings.historyLimit, 50)
    }

    func testSetHistoryLimit() {
        settings.historyLimit = 100
        XCTAssertEqual(settings.historyLimit, 100)
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), 100)
    }

    func testDefaultLaunchAtLogin() {
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testSetLaunchAtLogin() {
        settings.launchAtLogin = true
        XCTAssertTrue(settings.launchAtLogin)
    }

    func testDefaultSelectedModel() {
        XCTAssertEqual(settings.selectedModelName, "tiny")
    }

    func testSetSelectedModel() {
        settings.selectedModelName = "base.en"
        XCTAssertEqual(settings.selectedModelName, "base.en")
    }

    func testDefaultAudioInputDeviceID() {
        XCTAssertNil(settings.audioInputDeviceID)
    }

    func testSetAudioInputDeviceID() {
        settings.audioInputDeviceID = "BuiltInMic:42"
        XCTAssertEqual(settings.audioInputDeviceID, "BuiltInMic:42")
    }

    func testDefaultHotkeyKeyCode() {
        XCTAssertNil(settings.hotkeyKeyCode)
    }

    func testSetHotkey() {
        settings.hotkeyKeyCode = 49
        settings.hotkeyModifierFlags = 256
        XCTAssertEqual(settings.hotkeyKeyCode, 49)
        XCTAssertEqual(settings.hotkeyModifierFlags, 256)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Cmd+U` in Xcode or `xcodebuild test -scheme VoxScribe -destination 'platform=macOS'`
Expected: All tests fail -- `AppSettings` type does not exist.

- [ ] **Step 3: Implement AppSettings**

Create `VoxScribe/Settings/AppSettings.swift`:

```swift
import Foundation

/// Manages all user-configurable settings via UserDefaults.
///
/// Provides typed access to persisted preferences including hotkey
/// configuration, model selection, audio input device, history limit,
/// and launch-at-login state.
///
/// - Parameter defaults: The UserDefaults suite to use. Defaults to `.standard`.
final class AppSettings {
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
        set { defaults.set(newValue, forKey: "selectedModelName") }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Cmd+U` in Xcode
Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Settings/AppSettings.swift VoxScribeTests/AppSettingsTests.swift
git commit -m "feat: add AppSettings UserDefaults wrapper

Typed access to all user preferences: hotkey key code and modifier flags,
selected whisper model, audio input device ID, history limit, and
launch-at-login. Includes full test coverage with isolated UserDefaults suite."
```

---

## Task 3: HistoryEntry + ClipboardHistory

**Files:**
- Create: `VoxScribe/History/HistoryEntry.swift`
- Create: `VoxScribe/History/ClipboardHistory.swift`
- Create: `VoxScribeTests/HistoryEntryTests.swift`
- Create: `VoxScribeTests/ClipboardHistoryTests.swift`

- [ ] **Step 1: Write failing tests for HistoryEntry**

Create `VoxScribeTests/HistoryEntryTests.swift`:

```swift
import XCTest
@testable import VoxScribe

final class HistoryEntryTests: XCTestCase {
    func testPreviewTruncatesLongText() {
        let entry = HistoryEntry(
            text: String(repeating: "a", count: 100),
            timestamp: Date()
        )
        XCTAssertEqual(entry.preview.count, 53)
        XCTAssertTrue(entry.preview.hasSuffix("..."))
    }

    func testPreviewKeepsShortText() {
        let entry = HistoryEntry(text: "Short text", timestamp: Date())
        XCTAssertEqual(entry.preview, "Short text")
    }

    func testCodableRoundTrip() throws {
        let entry = HistoryEntry(text: "Hello world", timestamp: Date(timeIntervalSince1970: 1000))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.text, entry.text)
        XCTAssertEqual(decoded.timestamp, entry.timestamp)
    }

    func testRelativeTimestampJustNow() {
        let entry = HistoryEntry(text: "test", timestamp: Date())
        XCTAssertEqual(entry.relativeTimestamp, "just now")
    }

    func testRelativeTimestampMinutesAgo() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let entry = HistoryEntry(text: "test", timestamp: fiveMinutesAgo)
        XCTAssertEqual(entry.relativeTimestamp, "5 min ago")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Cmd+U` in Xcode
Expected: Fail -- `HistoryEntry` type does not exist.

- [ ] **Step 3: Implement HistoryEntry**

Create `VoxScribe/History/HistoryEntry.swift`:

```swift
import Foundation

/// A single transcription result stored in clipboard history.
///
/// Contains the full transcription text, the timestamp when it was created,
/// and computed properties for display in the menu bar submenu.
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date

    /// Creates a new history entry.
    ///
    /// - Parameters:
    ///   - text: The full transcription text.
    ///   - timestamp: When the transcription was created.
    ///   - id: Unique identifier. Defaults to a new UUID.
    init(text: String, timestamp: Date, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }

    /// A truncated preview of the transcription text (first 50 characters + "...").
    var preview: String {
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(50)) + "..."
    }

    /// A human-readable relative timestamp (e.g., "5 min ago", "2 hr ago").
    var relativeTimestamp: String {
        let elapsed = Int(Date().timeIntervalSince(timestamp))
        switch elapsed {
        case ..<60:
            return "just now"
        case 60..<3600:
            let minutes = elapsed / 60
            return "\(minutes) min ago"
        case 3600..<86400:
            let hours = elapsed / 3600
            return "\(hours) hr ago"
        default:
            let days = elapsed / 86400
            return "\(days) day ago"
        }
    }
}
```

- [ ] **Step 4: Run HistoryEntry tests to verify they pass**

Run: `Cmd+U` in Xcode
Expected: All 5 HistoryEntry tests pass.

- [ ] **Step 5: Write failing tests for ClipboardHistory**

Create `VoxScribeTests/ClipboardHistoryTests.swift`:

```swift
import XCTest
@testable import VoxScribe

final class ClipboardHistoryTests: XCTestCase {
    private var history: ClipboardHistory!
    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_history_\(UUID().uuidString).json")
        history = ClipboardHistory(fileURL: tempFileURL, limit: 5)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testAddEntryAppendsToFront() {
        history.addEntry(text: "First")
        history.addEntry(text: "Second")
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries[0].text, "Second")
        XCTAssertEqual(history.entries[1].text, "First")
    }

    func testAddEntryPrunesWhenOverLimit() {
        for i in 1...7 {
            history.addEntry(text: "Entry \(i)")
        }
        XCTAssertEqual(history.entries.count, 5)
        XCTAssertEqual(history.entries[0].text, "Entry 7")
        XCTAssertEqual(history.entries[4].text, "Entry 3")
    }

    func testPersistenceRoundTrip() {
        history.addEntry(text: "Persisted entry")
        let loaded = ClipboardHistory(fileURL: tempFileURL, limit: 5)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries[0].text, "Persisted entry")
    }

    func testClearRemovesAllEntries() {
        history.addEntry(text: "Entry 1")
        history.addEntry(text: "Entry 2")
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testClearDeletesFile() {
        history.addEntry(text: "Entry")
        history.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    func testUpdateLimitPrunesExcess() {
        for i in 1...5 {
            history.addEntry(text: "Entry \(i)")
        }
        history.updateLimit(3)
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.entries[0].text, "Entry 5")
    }

    func testLoadFromEmptyFileReturnsEmptyEntries() {
        let fresh = ClipboardHistory(fileURL: tempFileURL, limit: 10)
        XCTAssertTrue(fresh.entries.isEmpty)
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `Cmd+U` in Xcode
Expected: Fail -- `ClipboardHistory` type does not exist.

- [ ] **Step 7: Implement ClipboardHistory**

Create `VoxScribe/History/ClipboardHistory.swift`:

```swift
import Foundation

/// Manages a persisted list of transcription history entries.
///
/// Entries are stored in memory and written to a JSON file on disk after
/// each mutation. The list is capped at a configurable limit, with the
/// oldest entries pruned first.
///
/// - Parameters:
///   - fileURL: The file URL where history is persisted as JSON.
///   - limit: The maximum number of entries to retain.
final class ClipboardHistory {
    private(set) var entries: [HistoryEntry]
    private let fileURL: URL
    private var limit: Int

    /// Creates a ClipboardHistory, loading existing entries from disk if available.
    ///
    /// - Parameters:
    ///   - fileURL: Path to the JSON persistence file.
    ///   - limit: Maximum number of entries to keep.
    init(fileURL: URL, limit: Int) {
        self.fileURL = fileURL
        self.limit = limit
        self.entries = []
        loadFromDisk()
    }

    /// Adds a new transcription to the history.
    ///
    /// The entry is inserted at the front (most recent first). If the total
    /// count exceeds the limit, the oldest entries are removed. The updated
    /// list is persisted to disk.
    ///
    /// - Parameter text: The full transcription text.
    func addEntry(text: String) {
        let entry = HistoryEntry(text: text, timestamp: Date())
        entries.insert(entry, at: 0)
        pruneToLimit()
        saveToDisk()
    }

    /// Removes all history entries and deletes the persistence file.
    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Updates the maximum entry limit and prunes excess entries.
    ///
    /// - Parameter newLimit: The new maximum number of entries to retain.
    func updateLimit(_ newLimit: Int) {
        limit = newLimit
        pruneToLimit()
        saveToDisk()
    }

    /// Removes entries beyond the configured limit, keeping the most recent.
    private func pruneToLimit() {
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
    }

    /// Writes the current entries to the JSON file on disk.
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    /// Loads entries from the JSON file on disk if it exists.
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            NSLog("Failed to load clipboard history: \(error.localizedDescription)")
            entries = []
        }
    }
}
```

- [ ] **Step 8: Run all tests to verify they pass**

Run: `Cmd+U` in Xcode
Expected: All HistoryEntry (5) and ClipboardHistory (7) tests pass.

- [ ] **Step 9: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/History/ VoxScribeTests/HistoryEntryTests.swift VoxScribeTests/ClipboardHistoryTests.swift
git commit -m "feat: add HistoryEntry and ClipboardHistory

HistoryEntry is a Codable struct with preview truncation and relative
timestamps. ClipboardHistory manages a capped, persisted list of
entries backed by a JSON file. Full test coverage for both."
```

---

## Task 4: WhisperModel Metadata

**Files:**
- Create: `VoxScribe/Models/WhisperModel.swift`
- Create: `VoxScribeTests/WhisperModelTests.swift`

- [ ] **Step 1: Write failing tests for WhisperModel**

Create `VoxScribeTests/WhisperModelTests.swift`:

```swift
import XCTest
@testable import VoxScribe

final class WhisperModelTests: XCTestCase {
    func testAllModelsHaveUniqueNames() {
        let names = WhisperModel.allModels.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testAllModelsCount() {
        XCTAssertEqual(WhisperModel.allModels.count, 9)
    }

    func testEnglishOnlyModelsAreMarked() {
        let englishOnly = WhisperModel.allModels.filter { $0.isEnglishOnly }
        XCTAssertEqual(englishOnly.count, 4)
        for model in englishOnly {
            XCTAssertTrue(model.name.hasSuffix(".en"))
        }
    }

    func testFilenameFormat() {
        let tiny = WhisperModel.allModels.first { $0.name == "tiny" }!
        XCTAssertEqual(tiny.filename, "ggml-tiny.bin")
    }

    func testDownloadURLIsValid() {
        let base = WhisperModel.allModels.first { $0.name == "base" }!
        XCTAssertTrue(base.downloadURL.absoluteString.contains("ggml-base.bin"))
    }

    func testStorageDirectoryPath() {
        let expectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VoxScribe Models")
        XCTAssertEqual(WhisperModel.storageDirectory, expectedPath)
    }

    func testModelFilePath() {
        let tiny = WhisperModel.allModels.first { $0.name == "tiny" }!
        let expected = WhisperModel.storageDirectory.appendingPathComponent("ggml-tiny.bin")
        XCTAssertEqual(tiny.localFilePath, expected)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Cmd+U` in Xcode
Expected: Fail -- `WhisperModel` type does not exist.

- [ ] **Step 3: Implement WhisperModel**

Create `VoxScribe/Models/WhisperModel.swift`:

```swift
import Foundation

/// Metadata for a whisper.cpp model, including its name, download URL,
/// approximate file size, and whether it supports only English.
struct WhisperModel: Identifiable {
    let id: String
    let name: String
    let displaySize: String
    let isEnglishOnly: Bool

    /// The expected filename on disk (e.g., "ggml-tiny.bin").
    var filename: String {
        "ggml-\(name).bin"
    }

    /// The remote URL to download this model from Hugging Face.
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    /// The directory where all whisper models are stored.
    static let storageDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VoxScribe Models")
    }()

    /// The full local file path for this model.
    var localFilePath: URL {
        WhisperModel.storageDirectory.appendingPathComponent(filename)
    }

    /// Whether this model has been downloaded and exists on disk.
    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localFilePath.path)
    }

    /// All available whisper models in order from smallest to largest.
    static let allModels: [WhisperModel] = [
        WhisperModel(id: "tiny.en", name: "tiny.en", displaySize: "~75 MB", isEnglishOnly: true),
        WhisperModel(id: "tiny", name: "tiny", displaySize: "~75 MB", isEnglishOnly: false),
        WhisperModel(id: "base.en", name: "base.en", displaySize: "~142 MB", isEnglishOnly: true),
        WhisperModel(id: "base", name: "base", displaySize: "~142 MB", isEnglishOnly: false),
        WhisperModel(id: "small.en", name: "small.en", displaySize: "~466 MB", isEnglishOnly: true),
        WhisperModel(id: "small", name: "small", displaySize: "~466 MB", isEnglishOnly: false),
        WhisperModel(id: "medium.en", name: "medium.en", displaySize: "~1.5 GB", isEnglishOnly: true),
        WhisperModel(id: "medium", name: "medium", displaySize: "~1.5 GB", isEnglishOnly: false),
        WhisperModel(id: "large-v3", name: "large-v3", displaySize: "~3.1 GB", isEnglishOnly: false),
    ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Cmd+U` in Xcode
Expected: All 7 WhisperModel tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Models/WhisperModel.swift VoxScribeTests/WhisperModelTests.swift
git commit -m "feat: add WhisperModel metadata struct

Defines all 9 curated whisper models (4 English-only, 5 multilingual)
with download URLs, filenames, storage paths, and download state. Models
are stored in ~/Documents/VoxScribe Models/."
```

---

## Task 5: ModelManager (Download + Delete)

**Files:**
- Create: `VoxScribe/Models/ModelManager.swift`
- Create: `VoxScribeTests/ModelManagerTests.swift`

- [ ] **Step 1: Write failing tests for ModelManager**

Create `VoxScribeTests/ModelManagerTests.swift`:

```swift
import XCTest
@testable import VoxScribe

final class ModelManagerTests: XCTestCase {
    private var manager: ModelManager!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxscribe_test_models_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        manager = ModelManager(storageDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testDownloadedModelsInitiallyEmpty() {
        XCTAssertTrue(manager.downloadedModels().isEmpty)
    }

    func testDeleteModelRemovesFile() throws {
        let fakePath = tempDirectory.appendingPathComponent("ggml-tiny.bin")
        try Data("fake".utf8).write(to: fakePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakePath.path))

        let model = WhisperModel.allModels.first { $0.name == "tiny" }!
        try manager.deleteModel(model)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fakePath.path))
    }

    func testDeleteNonexistentModelThrows() {
        let model = WhisperModel.allModels.first { $0.name == "large-v3" }!
        XCTAssertThrowsError(try manager.deleteModel(model))
    }

    func testDownloadedModelsListsExistingFiles() throws {
        let fakePath = tempDirectory.appendingPathComponent("ggml-base.bin")
        try Data("fake".utf8).write(to: fakePath)
        let downloaded = manager.downloadedModels()
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded[0].name, "base")
    }

    func testSmallestDownloadedModel() throws {
        let tinyPath = tempDirectory.appendingPathComponent("ggml-tiny.bin")
        let basePath = tempDirectory.appendingPathComponent("ggml-base.bin")
        try Data("fake".utf8).write(to: tinyPath)
        try Data("fake".utf8).write(to: basePath)
        let smallest = manager.smallestDownloadedModel()
        XCTAssertEqual(smallest?.name, "tiny")
    }

    func testSmallestDownloadedModelNilWhenEmpty() {
        XCTAssertNil(manager.smallestDownloadedModel())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Cmd+U` in Xcode
Expected: Fail -- `ModelManager` type does not exist.

- [ ] **Step 3: Implement ModelManager**

Create `VoxScribe/Models/ModelManager.swift`:

```swift
import Foundation

/// Manages downloading, deleting, and querying whisper model files on disk.
///
/// Models are stored as `.bin` files in a configurable storage directory
/// (defaults to `~/Documents/VoxScribe Models/`). Downloads are performed
/// via `URLSession` with progress reporting through a closure.
final class ModelManager: ObservableObject {
    private let storageDirectory: URL
    @Published var activeDownloads: [String: Double] = [:]

    /// Creates a ModelManager with a custom storage directory.
    ///
    /// - Parameter storageDirectory: Where to store downloaded model files.
    ///   Defaults to `WhisperModel.storageDirectory`.
    init(storageDirectory: URL = WhisperModel.storageDirectory) {
        self.storageDirectory = storageDirectory
        ensureStorageDirectoryExists()
    }

    /// Returns all models that have been downloaded and exist on disk.
    ///
    /// - Returns: An array of `WhisperModel` values whose files are present
    ///   in the storage directory, ordered from smallest to largest.
    func downloadedModels() -> [WhisperModel] {
        WhisperModel.allModels.filter { model in
            let path = storageDirectory.appendingPathComponent(model.filename)
            return FileManager.default.fileExists(atPath: path.path)
        }
    }

    /// Returns the smallest downloaded model, or nil if no models are downloaded.
    ///
    /// - Returns: The smallest available `WhisperModel`, or nil.
    func smallestDownloadedModel() -> WhisperModel? {
        downloadedModels().first
    }

    /// Deletes a downloaded model file from disk.
    ///
    /// - Parameter model: The model to delete.
    /// - Throws: An error if the file does not exist or cannot be removed.
    func deleteModel(_ model: WhisperModel) throws {
        let path = storageDirectory.appendingPathComponent(model.filename)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ModelManagerError.modelNotFound(model.name)
        }
        try FileManager.default.removeItem(at: path)
    }

    /// Downloads a model from its remote URL to the storage directory.
    ///
    /// Progress is reported via the `activeDownloads` published property,
    /// keyed by model name (0.0 to 1.0).
    ///
    /// - Parameters:
    ///   - model: The model to download.
    ///   - completion: Called on the main queue when the download finishes
    ///     or fails. Receives a `Result<URL, Error>` with the local file path.
    func downloadModel(
        _ model: WhisperModel,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let destinationPath = storageDirectory.appendingPathComponent(model.filename)
        let delegate = DownloadDelegate(
            modelName: model.name,
            destination: destinationPath,
            manager: self,
            completion: completion
        )
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        let task = session.downloadTask(with: model.downloadURL)
        DispatchQueue.main.async {
            self.activeDownloads[model.name] = 0.0
        }
        task.resume()
    }

    /// Checks whether a specific model file exists on disk.
    ///
    /// - Parameter model: The model to check.
    /// - Returns: `true` if the model file is present in the storage directory.
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = storageDirectory.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Creates the storage directory if it does not already exist.
    private func ensureStorageDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }
}

/// Errors specific to model management operations.
enum ModelManagerError: LocalizedError {
    case modelNotFound(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model '\(name)' not found on disk."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}

/// URLSession delegate that handles download progress and file relocation.
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let modelName: String
    let destination: URL
    weak var manager: ModelManager?
    let completion: (Result<URL, Error>) -> Void

    init(
        modelName: String,
        destination: URL,
        manager: ModelManager,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.modelName = modelName
        self.destination = destination
        self.manager = manager
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            DispatchQueue.main.async {
                self.manager?.activeDownloads.removeValue(forKey: self.modelName)
                self.completion(.success(self.destination))
            }
        } catch {
            DispatchQueue.main.async {
                self.manager?.activeDownloads.removeValue(forKey: self.modelName)
                self.completion(.failure(error))
            }
        }
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.manager?.activeDownloads[self.modelName] = progress
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            DispatchQueue.main.async {
                self.manager?.activeDownloads.removeValue(forKey: self.modelName)
                self.completion(.failure(error))
            }
        }
        session.invalidateAndCancel()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Cmd+U` in Xcode
Expected: All 6 ModelManager tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Models/ModelManager.swift VoxScribeTests/ModelManagerTests.swift
git commit -m "feat: add ModelManager for downloading and deleting whisper models

Supports downloading models from Hugging Face with progress tracking,
deleting models from disk, listing downloaded models, and finding the
smallest available model for fallback. Uses URLSession delegate for
download progress reporting."
```

---

## Task 6: TranscriptionEngine (whisper.cpp Wrapper)

**Files:**
- Create: `VoxScribe/Transcription/TranscriptionEngine.swift`

- [ ] **Step 1: Implement TranscriptionEngine**

Create `VoxScribe/Transcription/TranscriptionEngine.swift`:

```swift
import Foundation

/// Swift wrapper around the whisper.cpp C API for audio transcription.
///
/// Manages the lifecycle of a whisper model context, providing methods
/// to load models, run transcription on PCM audio files, and free resources.
/// All transcription runs on a background queue; results are delivered
/// on the main queue via completion closures.
///
/// - Important: Only one model is loaded at a time. Switching models
///   frees the previous context before loading the new one.
final class TranscriptionEngine {
    private var whisperContext: OpaquePointer?
    private let transcriptionQueue = DispatchQueue(
        label: "com.voxscribe.transcription",
        qos: .userInitiated
    )
    private(set) var isTranscribing = false
    private(set) var loadedModelName: String?

    /// Loads a whisper model from disk into memory.
    ///
    /// If another model is already loaded, it is freed first.
    ///
    /// - Parameter model: The whisper model whose local file should be loaded.
    /// - Throws: `TranscriptionError.modelLoadFailed` if the file cannot be
    ///   loaded by whisper.cpp.
    func loadModel(_ model: WhisperModel) throws {
        unloadModel()
        let path = model.localFilePath.path
        guard let context = whisper_init_from_file(path) else {
            throw TranscriptionError.modelLoadFailed(model.name)
        }
        whisperContext = context
        loadedModelName = model.name
        NSLog("Loaded whisper model: \(model.name)")
    }

    /// Frees the currently loaded model from memory.
    func unloadModel() {
        if let context = whisperContext {
            whisper_free(context)
            whisperContext = nil
            loadedModelName = nil
            NSLog("Unloaded whisper model")
        }
    }

    /// Transcribes a 16kHz mono PCM audio file to text.
    ///
    /// The transcription runs on a background queue. The completion handler
    /// is called on the main queue with either the transcribed text or an error.
    ///
    /// - Parameters:
    ///   - audioFileURL: Path to a 16kHz mono Float32 PCM file (no header).
    ///   - completion: Called on the main queue with the transcription result.
    func transcribe(
        audioFileURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let context = whisperContext else {
            DispatchQueue.main.async {
                completion(.failure(TranscriptionError.noModelLoaded))
            }
            return
        }

        isTranscribing = true

        transcriptionQueue.async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isTranscribing = false
                }
            }

            do {
                let samples = try self?.loadPCMSamples(from: audioFileURL) ?? []
                if samples.isEmpty {
                    DispatchQueue.main.async {
                        completion(.failure(TranscriptionError.emptyAudio))
                    }
                    return
                }

                var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                params.language = nil  // auto-detect language
                params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
                params.print_progress = false
                params.print_timestamps = false

                let result = samples.withUnsafeBufferPointer { bufferPointer in
                    whisper_full(
                        context,
                        params,
                        bufferPointer.baseAddress,
                        Int32(bufferPointer.count)
                    )
                }

                guard result == 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(TranscriptionError.transcriptionFailed))
                    }
                    return
                }

                let segmentCount = whisper_full_n_segments(context)
                var transcription = ""
                for i in 0..<segmentCount {
                    if let cString = whisper_full_get_segment_text(context, i) {
                        transcription += String(cString: cString)
                    }
                }

                let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion(.success(trimmed))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Reads raw Float32 PCM samples from a file.
    ///
    /// - Parameter url: Path to the PCM audio file.
    /// - Returns: An array of Float32 samples.
    /// - Throws: An error if the file cannot be read.
    private func loadPCMSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let sampleCount = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { buffer in
            data.copyBytes(to: buffer)
        }
        return samples
    }

    deinit {
        unloadModel()
    }
}

/// Errors that can occur during transcription operations.
enum TranscriptionError: LocalizedError {
    case modelLoadFailed(String)
    case noModelLoaded
    case emptyAudio
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let name):
            return "Failed to load whisper model '\(name)'."
        case .noModelLoaded:
            return "No whisper model is loaded."
        case .emptyAudio:
            return "Audio file contains no samples."
        case .transcriptionFailed:
            return "Transcription failed."
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Compiles successfully. The whisper.cpp C API functions resolve through the bridging header.

- [ ] **Step 3: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Transcription/TranscriptionEngine.swift
git commit -m "feat: add TranscriptionEngine wrapping whisper.cpp C API

Manages model lifecycle (load/unload/switch) and runs transcription
on a background queue. Reads raw PCM Float32 samples, calls whisper_full
with auto-detect language, and returns concatenated segment text.
Model stays loaded in memory between transcriptions for performance."
```

---

## Task 7: AudioRecorder (AVAudioEngine Wrapper)

**Files:**
- Create: `VoxScribe/Recording/AudioRecorder.swift`

- [ ] **Step 1: Implement AudioRecorder**

Create `VoxScribe/Recording/AudioRecorder.swift`:

```swift
import AVFoundation
import Foundation

/// Records audio from a selected input device to a temporary 16kHz mono PCM file.
///
/// Uses `AVAudioEngine` to capture audio and writes samples to disk in real time
/// to minimize memory usage. The engine tap is removed and the engine stopped
/// as soon as recording ends.
///
/// - Important: Callers must request microphone permission before starting
///   a recording.
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var outputFile: FileHandle?
    private var tempFileURL: URL?
    private(set) var isRecording = false

    /// The CoreAudio device ID to record from, or nil for the system default.
    var inputDeviceID: AudioDeviceID?

    /// Starts recording audio to a temporary PCM file.
    ///
    /// Audio is captured at 16kHz mono Float32, which is the format whisper.cpp
    /// expects. The temporary file is created in `NSTemporaryDirectory()`.
    ///
    /// - Throws: `AudioRecorderError.alreadyRecording` if a recording is in progress,
    ///   or `AudioRecorderError.engineStartFailed` if the audio engine cannot start.
    func startRecording() throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let engine = AVAudioEngine()

        if let deviceID = inputDeviceID {
            setInputDevice(deviceID, on: engine)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatConversionFailed
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voxscribe_recording_\(UUID().uuidString).pcm")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.convertAndWrite(
                buffer: buffer,
                converter: converter,
                targetFormat: targetFormat,
                fileHandle: fileHandle
            )
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            fileHandle.closeFile()
            try? FileManager.default.removeItem(at: tempURL)
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }

        audioEngine = engine
        outputFile = fileHandle
        tempFileURL = tempURL
        isRecording = true
        NSLog("Recording started")
    }

    /// Stops the current recording and returns the path to the temporary PCM file.
    ///
    /// The audio engine is stopped, the tap is removed, and the file handle
    /// is closed. The caller is responsible for deleting the temp file after
    /// transcription.
    ///
    /// - Returns: The URL of the recorded PCM audio file.
    /// - Throws: `AudioRecorderError.notRecording` if no recording is in progress.
    func stopRecording() throws -> URL {
        guard isRecording, let engine = audioEngine, let fileHandle = outputFile,
              let fileURL = tempFileURL else {
            throw AudioRecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        fileHandle.closeFile()

        audioEngine = nil
        outputFile = nil
        tempFileURL = nil
        isRecording = false

        NSLog("Recording stopped: \(fileURL.lastPathComponent)")
        return fileURL
    }

    /// Converts an audio buffer to 16kHz mono and writes it to the output file.
    ///
    /// - Parameters:
    ///   - buffer: The captured audio buffer from the engine tap.
    ///   - converter: The format converter (input format -> 16kHz mono).
    ///   - targetFormat: The target AVAudioFormat (16kHz mono Float32).
    ///   - fileHandle: The file handle to write converted samples to.
    private func convertAndWrite(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        fileHandle: FileHandle
    ) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (16000.0 / buffer.format.sampleRate)
        )
        guard frameCapacity > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCapacity
        ) else { return }

        var inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            NSLog("Audio conversion error: \(error.localizedDescription)")
            return
        }

        guard let channelData = convertedBuffer.floatChannelData else { return }
        let data = Data(
            bytes: channelData[0],
            count: Int(convertedBuffer.frameLength) * MemoryLayout<Float>.size
        )
        fileHandle.write(data)
    }

    /// Sets the audio input device on the engine via CoreAudio.
    ///
    /// - Parameters:
    ///   - deviceID: The CoreAudio AudioDeviceID to use.
    ///   - engine: The AVAudioEngine whose input node should be configured.
    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) {
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        var deviceIDValue = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDValue,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    deinit {
        if isRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            outputFile?.closeFile()
            if let url = tempFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// Errors specific to audio recording operations.
enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case engineStartFailed(String)
    case formatConversionFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is in progress."
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .formatConversionFailed:
            return "Failed to create audio format converter."
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Compiles successfully.

- [ ] **Step 3: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Recording/AudioRecorder.swift
git commit -m "feat: add AudioRecorder using AVAudioEngine

Records to a temporary 16kHz mono Float32 PCM file suitable for
whisper.cpp input. Supports selecting a specific CoreAudio input device.
Streams audio to disk during recording to minimize memory usage.
Cleans up engine tap and file handle on stop and in deinit."
```

---

## Task 8: AudioDeviceManager

**Files:**
- Create: `VoxScribe/Recording/AudioDeviceManager.swift`

- [ ] **Step 1: Implement AudioDeviceManager**

Create `VoxScribe/Recording/AudioDeviceManager.swift`:

```swift
import CoreAudio
import Foundation

/// Represents an audio input device available on the system.
struct AudioInputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

/// Enumerates and monitors available audio input devices via CoreAudio.
///
/// Publishes changes to the device list when devices are connected or
/// disconnected, allowing the UI to update dynamically.
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevices()
        installDeviceChangeListener()
    }

    /// Returns the system default input device ID, or nil if unavailable.
    ///
    /// - Returns: The `AudioDeviceID` of the default input device.
    var defaultInputDeviceID: AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Refreshes the list of available audio input devices.
    func refreshDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        let devices = deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard hasInputChannels(deviceID) else { return nil }
            guard let name = deviceName(deviceID) else { return nil }
            let uid = deviceUID(deviceID) ?? "\(deviceID)"
            return AudioInputDevice(id: deviceID, name: name, uid: uid)
        }

        DispatchQueue.main.async {
            self.inputDevices = devices
        }
    }

    /// Checks whether a device has input channels.
    ///
    /// - Parameter deviceID: The CoreAudio device ID to check.
    /// - Returns: `true` if the device has at least one input channel.
    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        let getStatus = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &dataSize, bufferListPointer
        )
        guard getStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    /// Returns the display name of a CoreAudio device.
    ///
    /// - Parameter deviceID: The device to query.
    /// - Returns: The device name string, or nil on failure.
    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    /// Returns the unique identifier string for a CoreAudio device.
    ///
    /// - Parameter deviceID: The device to query.
    /// - Returns: The device UID string, or nil on failure.
    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr else { return nil }
        return uid as String
    }

    /// Installs a listener for device connection/disconnection changes.
    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    deinit {
        if let block = listenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Compiles successfully.

- [ ] **Step 3: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Recording/AudioDeviceManager.swift
git commit -m "feat: add AudioDeviceManager for CoreAudio input device enumeration

Lists available audio input devices with names and UIDs. Monitors
for device connect/disconnect events and refreshes the device list
automatically. Provides the system default input device ID for fallback."
```

---

## Task 9: GlobalHotkeyManager

**Files:**
- Create: `VoxScribe/Hotkey/GlobalHotkeyManager.swift`

- [ ] **Step 1: Implement GlobalHotkeyManager**

Create `VoxScribe/Hotkey/GlobalHotkeyManager.swift`:

```swift
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
```

- [ ] **Step 2: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Compiles successfully.

- [ ] **Step 3: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Hotkey/GlobalHotkeyManager.swift
git commit -m "feat: add GlobalHotkeyManager using CGEvent tap

Registers a system-wide keyboard shortcut that triggers a handler
closure when pressed. Supports configurable key code and modifier
flags. Requires Accessibility permissions. Cleans up the event tap
on unregister and in deinit."
```

---

## Task 10: StatusBarController (Menu Bar Icon + Click Handling)

**Files:**
- Create: `VoxScribe/MenuBar/StatusBarController.swift`

- [ ] **Step 1: Implement StatusBarController**

Create `VoxScribe/MenuBar/StatusBarController.swift`:

```swift
import Cocoa
import UserNotifications

/// The three states the menu bar icon can be in.
enum AppState {
    case idle
    case recording
    case transcribing
}

/// Manages the NSStatusItem in the menu bar, handling left-click toggle
/// and right-click context menu, icon state animations, and coordinating
/// the recording-transcription-clipboard pipeline.
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let audioRecorder: AudioRecorder
    private let transcriptionEngine: TranscriptionEngine
    private let clipboardHistory: ClipboardHistory
    private let settings: AppSettings
    private let modelManager: ModelManager
    private let audioDeviceManager: AudioDeviceManager

    private var animationTimer: Timer?
    private(set) var appState: AppState = .idle

    /// Creates a StatusBarController and sets up the menu bar icon.
    ///
    /// - Parameters:
    ///   - audioRecorder: The recorder for capturing audio.
    ///   - transcriptionEngine: The whisper.cpp wrapper for transcription.
    ///   - clipboardHistory: The history manager for storing transcriptions.
    ///   - settings: The app settings instance.
    ///   - modelManager: The model download/delete manager.
    ///   - audioDeviceManager: The audio input device enumerator.
    init(
        audioRecorder: AudioRecorder,
        transcriptionEngine: TranscriptionEngine,
        clipboardHistory: ClipboardHistory,
        settings: AppSettings,
        modelManager: ModelManager,
        audioDeviceManager: AudioDeviceManager
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionEngine = transcriptionEngine
        self.clipboardHistory = clipboardHistory
        self.settings = settings
        self.modelManager = modelManager
        self.audioDeviceManager = audioDeviceManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        updateIcon()
    }

    /// Configures the status bar button with click event handling.
    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Routes left clicks to toggle recording and right clicks to the context menu.
    ///
    /// - Parameter sender: The NSStatusBarButton that was clicked.
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleRecording()
        }
    }

    /// Toggles between recording and idle states. Called by both left-click
    /// and the global hotkey.
    func toggleRecording() {
        switch appState {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            break  // ignore clicks during transcription
        }
    }

    /// Starts audio recording and transitions the icon to the recording state.
    private func startRecording() {
        if let deviceUID = settings.audioInputDeviceID {
            let device = audioDeviceManager.inputDevices.first { $0.uid == deviceUID }
            audioRecorder.inputDeviceID = device?.id
        } else {
            audioRecorder.inputDeviceID = nil
        }

        do {
            try audioRecorder.startRecording()
            appState = .recording
            updateIcon()
            startRecordingAnimation()
        } catch {
            NSLog("Failed to start recording: \(error.localizedDescription)")
            sendNotification(title: "Recording Failed", body: error.localizedDescription)
        }
    }

    /// Stops recording, transitions to transcribing state, and starts transcription.
    private func stopRecordingAndTranscribe() {
        do {
            let audioURL = try audioRecorder.stopRecording()
            appState = .transcribing
            updateIcon()
            startTranscribingAnimation()

            transcriptionEngine.transcribe(audioFileURL: audioURL) { [weak self] result in
                self?.stopAnimation()
                switch result {
                case .success(let text):
                    self?.handleTranscriptionResult(text)
                case .failure(let error):
                    NSLog("Transcription failed: \(error.localizedDescription)")
                    self?.sendNotification(
                        title: "Transcription Failed",
                        body: error.localizedDescription
                    )
                }
                try? FileManager.default.removeItem(at: audioURL)
                self?.appState = .idle
                self?.updateIcon()
            }
        } catch {
            NSLog("Failed to stop recording: \(error.localizedDescription)")
            appState = .idle
            updateIcon()
        }
    }

    /// Copies transcription text to the clipboard, saves to history,
    /// and shows a notification.
    ///
    /// - Parameter text: The transcribed text.
    private func handleTranscriptionResult(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        clipboardHistory.addEntry(text: text)
        sendNotification(title: "VoxScribe", body: "Copied to clipboard")
    }

    /// Updates the menu bar icon based on the current app state.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        switch appState {
        case .idle:
            button.image = NSImage(
                systemSymbolName: "mic",
                accessibilityDescription: "VoxScribe - idle"
            )
        case .recording:
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "VoxScribe - recording"
            )
        case .transcribing:
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "VoxScribe - transcribing"
            )
        }
    }

    /// Starts the pulsing red animation for the recording state.
    private func startRecordingAnimation() {
        stopAnimation()
        var isRed = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            if isRed {
                button.image = NSImage(
                    systemSymbolName: "mic.fill",
                    accessibilityDescription: "VoxScribe - recording"
                )
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
            isRed.toggle()
        }
    }

    /// Starts the pulsing animation for the transcribing state.
    private func startTranscribingAnimation() {
        stopAnimation()
        var isHighlighted = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let button = self?.statusItem.button else { return }
            button.contentTintColor = isHighlighted ? .systemOrange : nil
            isHighlighted.toggle()
        }
    }

    /// Stops any running icon animation and resets the tint color.
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        statusItem.button?.contentTintColor = nil
    }

    /// Sends a macOS user notification.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Builds and displays the right-click context menu.
    private func showContextMenu() {
        let menu = MenuBuilder.buildMenu(
            clipboardHistory: clipboardHistory,
            audioDeviceManager: audioDeviceManager,
            settings: settings,
            modelManager: modelManager,
            statusBarController: self
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // reset so left click works again
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Will fail because `MenuBuilder` does not exist yet (that's Task 11). This is expected.

- [ ] **Step 3: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/MenuBar/StatusBarController.swift
git commit -m "feat: add StatusBarController for menu bar icon and recording toggle

Manages the NSStatusItem with three states (idle, recording, transcribing).
Left click toggles recording, right click opens context menu. Coordinates
the full pipeline: record -> transcribe -> clipboard -> notification.
Animates the icon with pulsing colors during recording and transcription."
```

---

## Task 11: MenuBuilder (Right-Click Context Menu)

**Files:**
- Create: `VoxScribe/MenuBar/MenuBuilder.swift`

- [ ] **Step 1: Implement MenuBuilder**

Create `VoxScribe/MenuBar/MenuBuilder.swift`:

```swift
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

        let settingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
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
        systemDefault.action = #selector(MenuActionHandler.perform)
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
            deviceItem.action = #selector(MenuActionHandler.perform)
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
                entryItem.action = #selector(MenuActionHandler.perform)
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
    @objc func perform() {
        closure()
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Compiles successfully. StatusBarController can now reference MenuBuilder.

- [ ] **Step 3: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/MenuBar/MenuBuilder.swift
git commit -m "feat: add MenuBuilder for right-click context menu

Constructs the context menu with audio input source selection (with
checkmarks), clipboard history submenu (preview + relative timestamp),
settings item, and quit. Uses MenuActionHandler to bridge closures
to NSMenuItem actions."
```

---

## Task 12: SettingsView (SwiftUI Popover)

**Files:**
- Create: `VoxScribe/Settings/SettingsView.swift`
- Create: `VoxScribe/Settings/HotkeyRecorderView.swift`

- [ ] **Step 1: Implement HotkeyRecorderView**

Create `VoxScribe/Settings/HotkeyRecorderView.swift`:

```swift
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
```

- [ ] **Step 2: Implement SettingsView**

Create `VoxScribe/Settings/SettingsView.swift`:

```swift
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
```

- [ ] **Step 3: Build to verify compilation**

Run: `Cmd+B` in Xcode
Expected: Compiles successfully.

- [ ] **Step 4: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/Settings/SettingsView.swift VoxScribe/Settings/HotkeyRecorderView.swift
git commit -m "feat: add SettingsView and HotkeyRecorderView

SwiftUI settings popover with sections for global hotkey recording,
audio input device picker, whisper model management (download/delete/
select with progress bars), clipboard history limit, and launch-at-login
toggle via SMAppService."
```

---

## Task 13: App Entry Point + Wiring Everything Together

**Files:**
- Modify: `VoxScribe/App/VoxScribeApp.swift`

- [ ] **Step 1: Update VoxScribeApp to wire all components**

Replace `VoxScribe/App/VoxScribeApp.swift` with:

```swift
import Cocoa
import UserNotifications

/// The main application delegate that initializes and wires all components.
///
/// Sets up the transcription engine, audio recorder, clipboard history,
/// model manager, settings, hotkey manager, and status bar controller.
/// Manages the app lifecycle including model loading on launch and
/// cleanup on termination.
@main
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
```

- [ ] **Step 2: Add `import ServiceManagement` to VoxScribeApp**

Already included in the code above via the `SMAppService` usage.

- [ ] **Step 3: Build and run the app**

Run: `Cmd+R` in Xcode
Expected: The app launches with a microphone icon in the menu bar. Right-clicking shows the context menu. No Dock icon appears. Left-clicking will fail gracefully if no model is downloaded (logs "No whisper models downloaded").

- [ ] **Step 4: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add VoxScribe/App/VoxScribeApp.swift
git commit -m "feat: wire all components in AppDelegate

Initializes settings, model manager, audio recorder, device manager,
transcription engine, clipboard history, status bar controller, and
global hotkey manager. Loads the selected whisper model on launch with
fallback to smallest available. Cleans up on termination."
```

---

## Task 14: Integration Testing + Polish

**Files:**
- Modify: `VoxScribe/App/Info.plist` (if needed)
- No new files

- [ ] **Step 1: Manual integration test -- model download**

1. Run the app (`Cmd+R`)
2. Right-click the menu bar icon
3. Click "Settings..."
4. In the Models section, click "Download" on the "tiny" model
5. Verify the progress bar updates and the model appears in `~/Documents/VoxScribe Models/`
6. Verify the model status changes to "Active" or shows "Use" / "Delete" buttons

- [ ] **Step 2: Manual integration test -- recording and transcription**

1. Ensure the "tiny" model is downloaded and active
2. Left-click the menu bar icon
3. Verify the icon animates (pulsing red)
4. Speak a sentence into the microphone
5. Left-click again to stop
6. Verify the icon shows the transcribing animation
7. Verify a notification appears saying "Copied to clipboard"
8. Paste (`Cmd+V`) into a text editor and verify the transcribed text

- [ ] **Step 3: Manual integration test -- clipboard history**

1. After a successful transcription, right-click the menu bar icon
2. Open the "Clipboard History" submenu
3. Verify the transcription appears with a preview and timestamp
4. Click on the history entry
5. Paste and verify it copied the full text

- [ ] **Step 4: Manual integration test -- hotkey**

1. Right-click > Settings > set a hotkey (e.g., Cmd+Shift+R)
2. Close the settings
3. Press the hotkey from any app
4. Verify recording starts (icon animates)
5. Press the hotkey again
6. Verify transcription runs and result is copied to clipboard

- [ ] **Step 5: Manual integration test -- launch at login**

1. Right-click > Settings > enable "Launch at Login"
2. Log out and log back in (or restart)
3. Verify VoxScribe appears in the menu bar automatically

- [ ] **Step 6: Manual integration test -- audio input device**

1. Right-click the menu bar icon
2. Open "Audio Input Source"
3. Verify available devices are listed
4. Select a different device (if available)
5. Record and verify it captures from the selected device

- [ ] **Step 7: Add .gitignore**

Create `.gitignore` in the project root:

```
# Xcode
build/
*.xcworkspace
xcuserdata/
DerivedData/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.xccheckout
*.moved-aside

# macOS
.DS_Store
*.swp
*~

# Models (large binary files)
*.bin

# Superpowers planning files
docs/superpowers/
```

- [ ] **Step 8: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add .gitignore
git commit -m "chore: add .gitignore for Xcode, macOS, and model binaries

Excludes build artifacts, Xcode user data, DerivedData, .DS_Store,
whisper model binaries, and superpowers planning files."
```

- [ ] **Step 9: Create README.md**

Create `README.md`:

```markdown
# VoxScribe

A macOS menu bar app for local, offline voice-to-text transcription powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

## Features

- **Menu bar only** -- lives in the menu bar with no Dock icon or main window
- **One-click recording** -- left-click the microphone icon to start/stop
- **Global hotkey** -- configurable keyboard shortcut works from any app
- **Local transcription** -- all processing happens on-device using whisper.cpp
- **Auto-detect language** -- supports English, Mandarin Chinese, and 90+ languages
- **Clipboard integration** -- transcriptions are automatically copied to the clipboard
- **Clipboard history** -- access past transcriptions from the right-click menu
- **Multiple models** -- download and switch between 9 whisper models (tiny to large-v3)
- **Launch at login** -- optionally start with macOS

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (to build)
- Microphone access permission
- Accessibility permission (for global hotkey)

## Setup

1. Open `VoxScribe.xcodeproj` in Xcode
2. Initialize the whisper.cpp submodule:
   ```bash
   git submodule update --init --recursive
   ```
3. Build and run (`Cmd+R`)
4. Right-click the menu bar icon > Settings > download a whisper model
5. Left-click the menu bar icon or press your configured hotkey to start recording

## Model Storage

Whisper models are stored in `~/Documents/VoxScribe Models/`.

## Usage

| Action | Result |
|--------|--------|
| Left-click menu bar icon | Start/stop recording |
| Right-click menu bar icon | Open settings menu |
| Global hotkey (configurable) | Start/stop recording from any app |
```

- [ ] **Step 10: Commit**

```bash
cd /Users/marc/Projects/voxscribe
git add README.md
git commit -m "docs: add README with setup instructions and feature overview"
```
