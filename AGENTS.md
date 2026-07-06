# AGENTS.md — Reel

## Overview

**Reel** is a macOS menu-bar YouTube downloader built with SwiftUI, powered by `yt-dlp` and `ffmpeg`.
- Target: macOS 14+ (Sonoma), Apple Silicon & Intel
- Bundle ID: `com.waylake.reel`
- Project generation: `xcodegen` via `project.yml` (no SPM Package.swift)

## Architecture

```
Reel/
├── ReelApp.swift          # @main, MenuBarExtra + WindowGroup + Settings
├── Views/                 # SwiftUI views (MenuBarView, MainWindowView, SettingsView, etc.)
├── Stores/
│   ├── QueueStore.swift   # @Observable, single source of truth for download queue
│   ├── AppSettings.swift  # UserDefaults-backed settings
│   └── ClipboardMonitor.swift
├── Engine/
│   ├── DownloadEngine.swift   # actor, spawns yt-dlp Process, emits AsyncStream<EngineEvent>
│   ├── ArgumentBuilder.swift  # Maps DownloadOptions → yt-dlp CLI args
│   ├── ProgressParser.swift   # Parses yt-dlp stdout into EngineEvent
│   ├── BinaryResolver.swift   # Locates yt-dlp/ffmpeg binaries (app bundle or PATH)
│   └── MediaMetadata.swift    # Metadata pre-fetch model
├── Models/
│   ├── DownloadTask.swift     # @Observable queue item with snapshot persistence
│   ├── DownloadOptions.swift  # yt-dlp option mapping struct
│   ├── DownloadState.swift    # Enum: queued, downloading, encoding, paused, completed, failed, cancelled
│   └── Preset.swift           # Enum: bestMP4, 1080p, mp3, m4a, raw
└── Support/
    ├── Formatting.swift       # Fmt helper (duration, bytes, resolution)
    └── Theme.swift
```

### Key patterns
- **Concurrency**: `DownloadEngine` is an `actor`; `QueueStore` is `@MainActor @Observable`. Engine emits `AsyncStream<EngineEvent>`, consumed by `QueueStore`.
- **Persistence**: JSON snapshot in `~/Library/Application Support/Reel/queue.json`. No SwiftData/CoreData.
- **Scheduling**: `QueueStore.pump()` fills concurrency slots (max set in `AppSettings`).
- **Process control**: Pause/resume via `SIGSTOP`/`SIGCONT`; cancel via `Process.terminate()`.

## Build & Development

```bash
brew install yt-dlp ffmpeg
xcodegen generate        # regenerate .xcodeproj from project.yml
open Reel.xcodeproj
```

- No Swift Package Manager — this is an Xcode project managed by XcodeGen.
- `ENABLE_HARDENED_RUNTIME: true` in project.yml.
- Sandbox disabled (`com.apple.security.app-sandbox: false`).

## Coding Conventions

- **Language**: Korean for user-facing strings, comments, and commit messages.
- **Style**: Swift 5, SwiftUI with `@Observable` (not `ObservableObject`). Use `@MainActor` for UI state.
- **File naming**: PascalCase for types, one primary type per file.
- **No third-party dependencies** — pure Foundation/SwiftUI/AppKit.
- **Error handling**: `EngineError` enum with localized descriptions; surface user-friendly Korean messages.

## Testing

- Currently no automated test target. Manual testing via debug builds.
- When adding tests: create a test target in `project.yml`, use XCTest.

## Release

```bash
./scripts/build-release.sh   # builds Release, bundles yt-dlp + ffmpeg into .app
./scripts/bundle-binaries.sh # copies yt-dlp/ffmpeg into app Resources
./scripts/notarize.sh        # notarize with Apple (requires credentials)
```

## Important Notes

- yt-dlp and ffmpeg are bundled as binaries in `Reel.app/Contents/Resources/`. `BinaryResolver` prefers app bundle, falls back to `$PATH`.
- `LSUIElement: true` — menu-bar only, no Dock icon.
- Output directory defaults to `~/Movies/Reel`.
- SponsorBlock integration is opt-in via `DownloadOptions.sponsorBlock`.
