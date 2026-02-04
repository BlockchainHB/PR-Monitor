# PR Monitor (Menu Bar)

Monitor multi-agent PR checks and review comments from your macOS menu bar — no tab switching.

PR Monitor is built for teams using multiple PR-review agents and CI systems. It keeps track of check runs and agent comments across your repositories and tells you when everything is ready for review, so you can respond in one focused pass.

## Why This Exists

With multiple agent reviewers running in parallel, it’s easy to get stuck context-switching: waiting on checks, checking PRs repeatedly, and tracking which agent finished. PR Monitor centralizes that status in the menu bar and notifies you when it’s time to act.

## How It Works

- Connect to GitHub via Device Flow
- Select repositories to track
- Map agents to checks and comment authors
- See live status for each PR and agent
- Get notified when reviews are ready

## Screenshots

![Menu bar popover](docs/screenshots/menubar-popover.png)
![Settings: General](docs/screenshots/settings-general.png)
![Settings: Repositories](docs/screenshots/settings-repos.png)
![Settings: Agents](docs/screenshots/settings-agents.png)
![Notification example](docs/screenshots/notification-example.png)

## Quick Start

1. Open `PRMonitor.xcodeproj` in Xcode.
2. Run the `PRMonitor` app target.
3. Open **Settings** from the menu bar app.
4. Add tracked repositories (format: `owner/name`).
5. Configure agent mappings (check name pattern + comment author login).
6. Authenticate with GitHub via device flow.

## GitHub OAuth Setup (Device Flow)

1. Create a GitHub OAuth App in your GitHub settings.
2. Copy the **Client ID** and paste it into Settings → Account.
3. Click **Sign In**, then enter the code at the GitHub verification page.

Scopes requested: `repo` (required for private repositories). This app currently always requests `repo`; change the scope in `Sources/PRMonitor/Services/GitHubAuthService.swift` if you want a public-only build.

## Notes

- Polling runs every 60 seconds while open PRs are detected, and backs off to 10 minutes when no open PRs exist.
- Notifications fire when all agents are complete, and optionally per agent if enabled.

## Privacy

Tokens are stored locally in the macOS Keychain. No data is sent anywhere other than GitHub’s API.

## Requirements

- macOS 14+
- Xcode 15 recommended

## Contributing

See `CONTRIBUTING.md` for local setup and contribution guidelines.

## License

MIT — see `LICENSE`.
