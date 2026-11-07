# Contributing to Reel

Thanks for taking the time to contribute! This guide covers how to report bugs, suggest features and send code. It also lists the conventions the codebase follows.

By taking part, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug.** Open a [bug report](https://github.com/waylake/reel/issues/new?template=bug_report.yml).
- **Suggest a feature.** Open a [feature request](https://github.com/waylake/reel/issues/new?template=feature_request.yml). Reel is intentionally minimal, so explain the problem you want to solve, not only the solution.
- **Improve the docs.** Typos, unclear steps and missing screenshots are all fair game.
- **Send a pull request.** For anything larger than a small fix, please open an issue first so we can agree on the approach.

> **Download failing on one specific site?** Check whether plain `yt-dlp <url>` fails too. If it does, the issue belongs upstream at [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp/issues). Reel only wraps yt-dlp.

## Development setup

**Requirements**

- macOS 14 Sonoma or later
- Xcode 16 or later
- [Homebrew](https://brew.sh)

```bash
brew install xcodegen yt-dlp ffmpeg
git clone https://github.com/waylake/reel.git
cd reel
xcodegen generate
open Reel.xcodeproj
```

`Reel.xcodeproj` is generated from [`project.yml`](project.yml). **Never edit the project file by hand.** Change `project.yml` and run `xcodegen generate` again, for example after you add or remove a source file.

## Architecture in one minute

```
Clipboard / drop ──▶ QueueStore (@MainActor @Observable)
                        │  pump() fills concurrency slots
                        ▼
                    DownloadEngine (actor) ──▶ yt-dlp Process
                        │  AsyncStream<EngineEvent>
                        ▼
                    ProgressParser ──▶ DownloadTask updates ──▶ SwiftUI views
```

| Area | Where |
| --- | --- |
| UI (cards, menu bar, settings) | `Reel/Views/` |
| Queue, settings, clipboard, updater state | `Reel/Stores/` |
| yt-dlp process, CLI args, progress parsing, binary lookup | `Reel/Engine/` |
| Data models and download states | `Reel/Models/` |
| Design tokens (`Theme`), formatting, AppKit bridges | `Reel/Support/` |
| Notes on yt-dlp errors and YouTube quirks | [`docs/ytdlp-notes.md`](docs/ytdlp-notes.md) |

Key behaviors:

- **Persistence.** The queue is a JSON snapshot in `~/Library/Application Support/Reel/queue.json`. The app uses no Core Data or SwiftData.
- **Pause/resume.** The engine sends `SIGSTOP` / `SIGCONT` to the yt-dlp process.
- **User config.** Reel always passes `--ignore-config` so that a user's global yt-dlp config can't change its behavior.

## Code style

- **Swift 5 + SwiftUI**, with `@Observable`, not `ObservableObject`.
- **`@MainActor` for all UI state.** Keep process and I/O work in the `DownloadEngine` actor.
- **One type per file**, named in PascalCase after the type.
- **Use `Theme` tokens** for spacing, radii, fonts and colors. Spacing follows a 4pt grid, so avoid magic numbers in views.
- **Use system components first.** Use plain SwiftUI and AppKit before custom controls.
- **Keep dependencies minimal.** Sparkle is the only third-party dependency. Please discuss any new one in an issue first.
- **Errors** go through the `EngineError` enum with user-facing messages.
- **Language.** The UI and code comments are currently in Korean. Keep new UI strings consistent with the rest of the app. English is fine in issues, PRs and commit messages.

## Tests

```bash
# Unit tests and hosted view tests (XCTest + Swift Testing)
xcodebuild test -project Reel.xcodeproj -scheme Reel -destination 'platform=macOS'

# Smoke test: launches the built app, checks it stays alive, quits it cleanly
./scripts/smoke-test.sh
```

- Add or update tests in `ReelTests/` when you change parsing, argument building, retry policy or models.
- View tests render each view in every `DownloadState` to catch crashes. If you add a state or a view, extend them too.
- CI ([`test.yml`](.github/workflows/test.yml)) runs the full suite on every push and pull request.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org):

```
type(scope): short summary

Optional body explaining what changed and why.
```

| Type | Use for |
| --- | --- |
| `feat` | A user-facing feature |
| `fix` | A bug fix |
| `refactor` | A code change that adds no feature and fixes no bug |
| `perf` | A performance improvement |
| `test` | Tests only |
| `docs` | Documentation only |
| `build` / `ci` | `project.yml`, scripts, workflows |
| `chore` | Anything else |

Common scopes: `ui`, `engine`, `queue`, `settings`, `menubar`, `release`.

Examples: `fix(engine): retry on transient 403 from YouTube`, `feat(ui): show downloads as thumbnail cards`.

## Pull requests

1. Fork the repo and create a branch from `main` (`feat/card-layout`, `fix/progress-stall`, …).
2. Keep each PR focused on one change. Smaller PRs get reviewed faster.
3. Make sure `xcodebuild test` passes and the app launches.
4. **For UI changes, include before/after screenshots** in both light and dark mode if you can.
5. Fill in the [pull request template](.github/PULL_REQUEST_TEMPLATE.md) and link the issue (`Fixes #123`).

A maintainer will review your PR as soon as possible. Feedback is about the code, never about you.

## Releases (maintainers)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Commit, then tag and push: `git tag v1.3.0 && git push origin v1.3.0`.
3. [`release.yml`](.github/workflows/release.yml) builds the app, bundles `yt-dlp`/`ffmpeg`, signs the Sparkle update with `SPARKLE_PRIVATE_KEY` and publishes the zip and `appcast.xml` to GitHub Releases.

## License

By contributing, you agree to license your contributions under the [MIT License](LICENSE.md).
