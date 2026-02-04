# Contributing

Thanks for your interest in PR Monitor. Contributions are welcome.

## Getting Started

1. Clone the repo.
2. Open `PRMonitor.xcodeproj` in Xcode.
3. Run the `PRMonitor` target.

## Development Notes

- The app uses GitHub Device Flow for authentication.
- Tokens are stored in the macOS Keychain.
- Polling frequency is configurable in Settings.

## Code Style

- Prefer SwiftUI best practices and native macOS patterns.
- Avoid introducing new dependencies unless there is a clear benefit.
- Keep background work off the main thread; UI updates should be on the main actor.

## Testing

There is no automated test suite yet. If you add one, please include clear run instructions.

## Submitting Changes

1. Create a branch from `main`.
2. Make your changes and verify the app runs.
3. Open a pull request with a clear description of the change.

If your change is significant, please open an issue first to discuss the approach.

