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

1. Initialize the whisper.cpp submodule:
   ```bash
   git submodule update --init --recursive
   ```
2. Run the management script:
   ```bash
   ./app.sh
   ```
3. Select **Build & Install & Start** -- this builds the app, installs it to `/Applications`, and launches it
4. Grant **Microphone** and **Accessibility** permissions when prompted (System Settings > Privacy & Security)
5. Right-click the menu bar icon and download a whisper model
6. Start recording

## Model Storage

Whisper models are stored in `~/Documents/VoxScribe Models/`.

## Usage

| Action | Result |
|--------|--------|
| Left-click menu bar icon | Start/stop recording |
| Right-click menu bar icon | Open settings menu |
| Global hotkey (configurable) | Start/stop recording from any app |
