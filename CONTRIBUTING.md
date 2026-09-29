# Contributing

Thanks for your interest in PR Monitor. Issues and pull requests are welcome.

## Getting started

1. Clone the repo and open `PRMonitor.xcodeproj` in Xcode 26 or later.
2. Run the **PRMonitor** scheme (⌘R). The app appears in the menu bar.
3. Run the tests with ⌘U, or `swift test` from the command line.

Debug builds use their own keychain item, so they never touch the credentials of an installed release build. The quickest way to sign in while developing is **Continue with GitHub CLI**.

> **Tip:** if a command-line build fails at code signing with "resource fork, Finder information, or similar detritus not allowed", the checkout is inside a folder that adds extended attributes (such as an iCloud-synced `~/Documents`). Pass `-derivedDataPath` (Xcode) or `--scratch-path` (SwiftPM) pointing outside it.

## Where things live

| Folder | Contents |
| --- | --- |
| `Sources/PRMonitor/Core` | Pure domain logic: status engine, notification planner, polling policy. No I/O. |
| `Sources/PRMonitor/GitHub` | GraphQL client, queries, the two-phase fetcher, and auth (device flow, `gh`). |
| `Sources/PRMonitor/Services` | `@MainActor` models and system integration. |
| `Sources/PRMonitor/UI` | SwiftUI views and design tokens (`DesignSystem.swift`). |
| `Tests/PRMonitorTests` | Swift Testing suites and fixtures. |

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before larger changes.

## Guidelines

- **Status rules belong in `StatusEngine`**, with a test. If a PR is reported wrong, first reproduce it with `PRMonitor --diagnose owner/repo` (Debug builds), then write a failing test using the builders in `Fixtures.swift`.
- **Keep Core pure.** No networking or UI in Core, and time-dependent functions take `now` as a parameter so tests control the clock.
- **Measure GraphQL cost** when changing queries. Detail fields are paid for on every changed PR.
- **Follow the platform.** Use standard controls, macOS text styles and the tokens in `DesignSystem.swift`. Don't put glass on glass, and don't animate hover.
- **No new dependencies** without a strong reason.
- Refresh screenshots with the Debug-only tools in `Sources/PRMonitor/App/`. They always use fictional preview data:
  - `PRMonitor --showcase hero-light` (also `hero-dark`, `settings-light`, `settings-dark`) puts the real UI, on real Liquid Glass, over a designed backdrop and prints the rectangle to capture with `screencapture -x -R<rect> out.png`. These are the README images.
  - `PRMonitor --snapshot <dir>` renders the panel, Settings panes and every menu bar icon state offscreen, for quick layout checks.
  - `PRMonitor --diagnose owner/repo` checks status derivation against live repositories, using your `gh` token.
  - `PRMonitor --portfolio docs/screenshots/portfolio` renders portfolio images of the panel: transparent, exactly 2 px per point, cropped to the panel edge, in light and dark, plus a fully expanded variant. The folder is gitignored. For the matching 1024 px icon in its default style (regardless of the Mac's icon style setting), use Icon Composer's exporter:

    ```bash
    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" PRMonitorApp/AppIcon.icon --export-image --output-file docs/screenshots/portfolio/app-icon-1024.png --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
    ```

## Submitting changes

1. Branch from `main`.
2. Make sure `swift test` passes and the app builds.
3. Open a pull request describing the change and how you verified it. Include before and after screenshots for UI changes.

For significant changes, please open an issue first to discuss the approach.
