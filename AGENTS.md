# AGENTS.md — Reel

## Overview

**Reel** is a macOS menu-bar YouTube downloader built with SwiftUI, powered by `yt-dlp` and `ffmpeg`.
Targets macOS 14+ (Apple Silicon & Intel). Bundle ID: `com.waylake.reel`.
Project generated via `xcodegen` from `project.yml` (no SPM).

## Architecture

```
Reel/
├── ReelApp.swift          # @main entry point (MenuBarExtra + WindowGroup + Settings)
├── Views/                 # SwiftUI views
│   ├── MainWindowView.swift   # 메인 윈도우 — 썸네일 카드 그리드 (반투명 배경)
│   ├── DownloadCardView.swift # 큐 항목 카드
│   ├── MenuBarView.swift      # 메뉴바 팝오버 — 진행 중 + 최근 완료 미니 카드
│   └── SettingsView.swift     # 일반 / 다운로드 / 고급 탭
├── Stores/
│   ├── QueueStore.swift   # @Observable, single source of truth for download queue + persistence
│   ├── AppSettings.swift  # UserDefaults-backed settings
│   ├── ClipboardMonitor.swift
│   └── UpdaterStore.swift # Sparkle SPUStandardUpdaterController wrapper
├── Engine/
│   ├── DownloadEngine.swift   # actor — spawns yt-dlp Process, emits AsyncStream<EngineEvent>
│   ├── ArgumentBuilder.swift  # DownloadOptions → yt-dlp CLI arguments
│   ├── ProgressParser.swift   # yt-dlp stdout → EngineEvent
│   ├── BinaryResolver.swift   # Locates yt-dlp / ffmpeg (app bundle or $PATH)
│   └── MediaMetadata.swift    # Metadata pre-fetch model
├── Models/
│   ├── DownloadTask.swift     # @Observable queue item, snapshot persistence
│   ├── DownloadOptions.swift  # yt-dlp option mapping
│   ├── DownloadState.swift    # queued → downloading → encoding → completed / failed / cancelled
│   └── Preset.swift           # bestMP4 / 1080p / mp3 / m4a / raw
└── Support/
    ├── Formatting.swift       # Fmt helpers (duration, bytes, resolution)
    ├── Theme.swift
    └── VisualEffectBackground.swift  # NSVisualEffectView 브리지 (창 뒤 반투명)
```

### Concurrency

`DownloadEngine` is an `actor`. `QueueStore` is `@MainActor @Observable`.
The engine produces an `AsyncStream<EngineEvent>` consumed by the store.

### Persistence

Queue is serialized as JSON snapshots to `~/Library/Application Support/Reel/queue.json`.
No SwiftData or CoreData. Active downloads restart as queued on next launch.

### Scheduling

`QueueStore.pump()` fills concurrency slots up to `AppSettings.effectiveConcurrency`.
Pause/resume uses `SIGSTOP` / `SIGCONT`. Cancel sends `Process.terminate()`.

## Build

```bash
brew install yt-dlp ffmpeg
xcodegen generate        # regenerate .xcodeproj from project.yml
open Reel.xcodeproj
```

XcodeGen-managed project (no SPM). `ENABLE_HARDENED_RUNTIME` is on. Sandbox is off.

## Code Conventions

- User-facing strings, comments, commit messages: Korean
- Swift 5 + SwiftUI with `@Observable` (not `ObservableObject`)
- `@MainActor` for all UI state
- One type per file, PascalCase naming
- Minimal third-party dependencies (Sparkle for auto-updates)
- Errors via `EngineError` enum with localized Korean messages

## Testing

`ReelTests/` (XCTest + Swift Testing) — `xcodebuild test -project Reel.xcodeproj -scheme Reel -destination 'platform=macOS'`.
Smoke test: `./scripts/smoke-test.sh`. CI: `.github/workflows/test.yml`.

## Docs

Public docs are in English: `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/`.
README screenshots live in `docs/screenshots/`.

## Release & Auto-Update

Reel uses **Sparkle 2** for in-app updates.
Deployment is fully automated via GitHub Actions (`.github/workflows/release.yml`).

1. Push a tag starting with `v` (e.g., `git tag v1.0.0 && git push --tags`).
2. The pipeline builds the app, signs it, and runs `generate_appcast` using the EdDSA private key (`SPARKLE_PRIVATE_KEY` in GitHub Secrets).
3. The `.zip` and `appcast.xml` are uploaded to GitHub Releases automatically.

To build manually locally:

```bash
./scripts/build-release.sh   # Release build + bundles yt-dlp/ffmpeg into .app
./scripts/notarize.sh        # Apple notarization
```
