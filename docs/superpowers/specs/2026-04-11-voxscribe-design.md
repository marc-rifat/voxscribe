# VoxScribe -- Design Spec

## Overview

VoxScribe is a macOS menu bar-only app for voice-to-text transcription. It lives entirely in the menu bar (no Dock icon, no main window), uses whisper.cpp for local transcription, and copies results to the clipboard. The app supports multiple whisper models, configurable hotkeys, clipboard history, and launch at login.

## Tech Stack

- **Language:** Swift
- **UI Framework:** SwiftUI / AppKit (`NSStatusItem`)
- **Audio Capture:** AVAudioEngine
- **Transcription:** whisper.cpp via C bridging header
- **Persistence:** UserDefaults (settings), JSON file (clipboard history)
- **Login Item:** SMAppService (macOS 13+)
- **Architecture:** Pure Swift + whisper.cpp via direct C bridging (no subprocess, no Swift Package wrapper)

## 1. App Structure & Lifecycle

- Menu bar-only app (`LSUIElement = true`, no Dock icon, no main window)
- Entry point is a Swift `@main` App struct using `NSStatusItem`
- Launch at login via `SMAppService.mainApp` (macOS 13+ API)
- Single `NSStatusItem` with a microphone SF Symbol icon

### Menu Bar Icon States

| State         | Icon Appearance                                          |
|---------------|----------------------------------------------------------|
| Idle          | Static microphone icon                                   |
| Recording     | Microphone with pulsing red dot (animated)               |
| Transcribing  | Microphone with spinning/pulsing indicator (different color) |

## 2. Interaction Model

### Left Click (Toggle Recording)

- **Idle:** Start recording immediately, icon transitions to recording state.
- **Recording:** Stop recording, icon transitions to transcribing state, begin transcription.
- **Transcribing:** Ignored (no action until transcription completes).

### Right Click (Context Menu)

- **Audio Input Source** -- submenu listing available input devices, checkmark on the active one.
- **Clipboard History** -- submenu showing recent transcriptions (first ~50 characters + timestamp). Clicking an item copies the full text back to the clipboard.
- **Settings** -- opens a settings popover with:
  - Toggle hotkey configuration (key recorder)
  - Model management (download/delete models from curated list)
  - History limit (number input)
  - Launch at login toggle
  - Audio input source
- **Quit VoxScribe**

### Global Hotkey

- Single customizable toggle hotkey registered via `CGEvent` tap or `NSEvent.addGlobalMonitorForEvents`.
- Same behavior as left click (start/stop recording).

## 3. Audio Recording

- **AVAudioEngine** captures audio from the selected input device.
- Records to a temporary file in 16kHz mono PCM format (whisper.cpp's expected input).
- Temp file written to `NSTemporaryDirectory()`.
- After transcription completes, the temp audio file is deleted.

### Input Device Management

- Enumerate available input devices via CoreAudio.
- Store the user's selected device ID in `UserDefaults`.
- Fall back to the system default input if the saved device is unavailable (e.g., unplugged).
- Listen for device connect/disconnect notifications to update the device list dynamically.

### Memory Considerations

- `AVAudioEngine` is stopped and its tap removed as soon as recording ends.
- Audio buffers are not held in memory -- streamed to disk during recording.

## 4. Transcription Engine (whisper.cpp)

### Integration

- whisper.cpp source compiled directly into the Xcode project via a C bridging header.
- C API functions (`whisper_init_from_file`, `whisper_full`, `whisper_free`, etc.) called from a Swift wrapper class (`TranscriptionEngine`).

### Model Lifecycle

- Model loaded into memory on app launch (using the user's last-selected model).
- Model stays loaded for the app's duration -- avoids reload overhead per transcription.
- On model switch in settings, the current model is freed and the new one is loaded.
- On quit, the model is explicitly freed via `whisper_free`.

### Transcription Flow

1. Receive temp audio file path.
2. Read PCM samples from the file.
3. Run `whisper_full` with auto-detect language.
4. Extract text segments from the result.
5. Concatenate into a single string.
6. Copy to clipboard via `NSPasteboard`.
7. Save to clipboard history.
8. Show macOS notification ("Copied to clipboard").
9. Delete temp audio file.
10. Icon returns to idle state.

### Threading

- Transcription runs on a background `DispatchQueue` to keep the UI responsive.
- UI updates (icon state, notification) dispatch back to the main thread.

## 5. Model Management

### Curated Model List

| Model      | Type          | Approx. Size |
|------------|---------------|--------------|
| tiny.en    | English-only  | ~75 MB       |
| tiny       | Multilingual  | ~75 MB       |
| base.en    | English-only  | ~142 MB      |
| base       | Multilingual  | ~142 MB      |
| small.en   | English-only  | ~466 MB      |
| small      | Multilingual  | ~466 MB      |
| medium.en  | English-only  | ~1.5 GB      |
| medium     | Multilingual  | ~1.5 GB      |
| large-v3   | Multilingual  | ~3.1 GB      |

### Download & Storage

- Models downloaded from Hugging Face (ggerganov/whisper.cpp model repo) via `URLSession`.
- Stored in `~/Documents/VoxScribe Models/`.
- Download progress shown in the settings UI (progress bar per model).
- User can delete downloaded models from settings to free disk space.

### Fallback Behavior

- On launch, if the selected model file is missing (e.g., user deleted it manually), fall back to the smallest available downloaded model and show a notification.

## 6. Clipboard History

### Storage

- Persisted as a JSON file at `~/Documents/VoxScribe Models/history.json`.
- Each entry contains: transcription text, timestamp, truncated preview (first 50 characters).
- Configurable max limit (default: 50), stored in `UserDefaults`.
- When the limit is reached, the oldest entry is removed before adding a new one.

### Right-Click Submenu Display

- Each item shows: truncated preview + relative timestamp (e.g., "Hello, this is a test... -- 5 min ago").
- Most recent at the top.
- Clicking an item copies the full transcription text to `NSPasteboard`.

### File Management

- History loaded into memory on app launch.
- Written to disk after each new transcription.
- When the user reduces the history limit, excess entries are pruned immediately and saved.

## 7. Settings & Persistence

### UserDefaults Keys

- Selected audio input device ID
- Global toggle hotkey (key code + modifier flags)
- Selected whisper model name
- History limit (integer, default 50)
- Launch at login (boolean)

### Settings UI

- Opened via right-click menu "Settings" item.
- Presented as a popover anchored to the menu bar icon.
- Sections:
  - **Hotkey** -- click-to-record key recorder field.
  - **Audio Input** -- dropdown of available devices.
  - **Model** -- list of models with download/delete buttons and progress indicators.
  - **History** -- number field for max entries, "Clear All History" button.
  - **Launch at Login** -- toggle switch.

### Memory Management Summary

- `AVAudioEngine` tap removed and engine stopped after each recording.
- Temp audio files deleted after transcription.
- whisper model freed on model switch and app quit.
- History array capped at user-defined limit.
- No retain cycles -- delegates use `weak` references, closures use `[weak self]`.
