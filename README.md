# PR Monitor (Menu Bar)

A lightweight macOS menu bar app for monitoring PR checks and agent review comments across multiple GitHub repositories.

## Quick Start

1. Open `PRMonitor.xcodeproj` in Xcode.
2. Run the `PRMonitor` app target.
3. Open **Settings** from the menu bar app.
4. Add your tracked repositories (format: `owner/name`).
5. Configure agent mappings (check name pattern + comment author login).
6. Authenticate with GitHub via device flow.

## GitHub OAuth Setup (Device Flow)

1. Create a GitHub OAuth App in your GitHub settings.
2. Copy the **Client ID** and paste it into Settings → Auth.
3. Click **Start Device Sign-In**, then enter the code at the GitHub verification page.

Scopes requested: `repo` (needed for private repos). If you only use public repos, you can narrow it.

## Notes

- Polling runs every 60 seconds while open PRs are detected, and backs off to 10 minutes when no open PRs exist.
- Notifications fire when all agents are complete, and optionally per agent if enabled.
