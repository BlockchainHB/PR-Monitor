# Architecture

PR Monitor has one job: turn a noisy stream of GitHub signals into a small number of trustworthy answers. Is this pull request done? Does it need me? This document explains how the code is organized around that job, and the decisions behind it.

## Layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│ UI (SwiftUI)          MenuBarPanel · PullRequestRow · Settings panes      │
├──────────────────────────────────────────────────────────────────────────┤
│ Services (@MainActor) Monitor · Account · AppSettings · Notifier ·        │
│                       SystemEvents · LoginItem                            │
├──────────────────────────────────────────────────────────────────────────┤
│ GitHub                GitHubClient · PullRequestFetcher (actor) ·         │
│                       PullRequestQueries · DeviceFlow · GitHubCLI         │
├──────────────────────────────────────────────────────────────────────────┤
│ Core (pure)           PullRequest · StatusEngine · NotificationPlanner ·  │
│                       PollingPolicy · RepositoryID · Agent                │
└──────────────────────────────────────────────────────────────────────────┘
```

Dependencies only point downward. **Core** has no I/O and imports nothing but Foundation, which is why almost every behavioral rule is unit-tested without mocks: tests build a `PullRequest` value, run it through a pure function, and assert on the result.

## Data flow

1. `Monitor` runs one structured-concurrency loop: `poll()`, then `sleep(delay)`, repeated.
2. `PullRequestFetcher` returns plain `PullRequest` values (no DTOs leak past the GitHub layer).
3. `StatusEngine` reduces each PR to a `PullRequestReport`: per-agent states plus an overall status.
4. SwiftUI observes `Monitor`. At the same time `NotificationPlanner` diffs the new reports against the previous poll, and `Notifier` posts whatever it decides.

Settings changes flow back through the macOS 26 `Observations` async sequence. A change to *what* is fetched (token, repositories, interval) wakes the loop immediately. A change to *how* agents are interpreted re-runs the engine on cached data with no network round trip.

## Fetching: two phases, one request per ten repositories

GitHub's GraphQL API charges points for the connections you ask for, not the data you get back. Asking for full details on every open PR every minute costs about 26 points per repository, which exhausts the 5,000 point hourly budget with five repositories.

So the fetch is split:

| Phase | Query | Cost | When |
| --- | --- | --- | --- |
| **List** | Up to 10 repositories per request via aliases (`r0: repository(…)`), 50 open PRs each, only `id`, `updatedAt`, `headRefOid` and the roll-up `state` | ~1 point per repository | Every poll |
| **Detail** | `nodes(ids:)` for up to 20 PRs: check runs, commit statuses, check suites, review requests, latest reviews, review threads, comments | ~1 point per PR | Only for PRs that changed, are still running, were pushed in the last 10 minutes, have a bot review pending, or haven't been refreshed in 5 minutes |

The fingerprint (`updatedAt | headRefOid | rollupState`) catches pushes, comments, reviews and check transitions. The five-minute ceiling catches the few events that bump none of those, such as a resolved thread.

**Partial failures stay partial.** GraphQL returns `data` and `errors` together. Each error's `path[0]` maps back to its alias, so an inaccessible repository shows a warning in its section header while the rest of the list stays live. Stale data for that repository is kept rather than dropped, so no one sees a "new" PR notification when access returns.

Real-world validation: `PRMonitor --diagnose` runs this pipeline against live repositories. On a sample of five repositories and 17 PRs, a cold poll took about 5s and a cached poll about 1.1s.

## Status derivation

`StatusEngine` is deliberately boring: one pure function per concern, and no hidden state.

- **Automatic mode** groups signals by integration. Check runs group by app slug and commit statuses by creator, so twelve GitHub Actions jobs become one row. A bot whose login matches an app slug merges with it: Vercel's status, its "Preview Comments" check run and its account are one agent. Review-only bots (Codex, Copilot) become agents through review requests, reviews and threads. Comment-only bots (changeset, codecov) are ignored because they have no lifecycle.
- **Custom mode** matches user-defined agents by check pattern and/or bot login. Logins are normalized, so `cursor[bot]` (REST), `cursor` (GraphQL) and `Cursor` compare equal.
- **Precedence**: Failing › Running › Needs review › Ready. A failure is actionable even while other agents run.
- **Accuracy edge cases**, each covered by a test:
  - A pending review request means the bot is still reviewing (GitHub removes the request on submit).
  - A review attached to an older commit SHA is treated as "about to re-review" for three minutes after a push, then as passed.
  - A configured agent that hasn't reported within three minutes of a push is treated as not applicable, rather than "waiting" forever. The 0.x version did the latter.
  - Workflows awaiting approval have a check suite but no check runs, so they're surfaced from `checkSuites`.
  - If the roll-up says `PENDING` but no visible check is pending, the engine trusts GitHub.
  - Skipped, neutral, cancelled and stale checks are not failures.

## Notifications

`NotificationPlanner` is a pure value type that diffs snapshots:

- The **first poll records a baseline**, so launching the app never floods Notification Center.
- Lifecycles are keyed by **head commit SHA**. Each push can announce "settled" at most once. None of the similar open-source projects surveyed does this. They key by PR or by status text, and re-announce when unrelated activity bumps `updatedAt`.
- **Regressions** (a bot leaves threads after its check passed) produce one follow-up.
- PRs that existed before launch aren't announced when they first appear, for example after enabling a repository.
- Identifiers are deterministic (`owner/repo#12@<sha>/settled-ready`), so a re-plan replaces a banner instead of stacking a duplicate.
- Permission is requested **in context**, the first time there's something worth saying, not on first launch.

## Polling

`PollingPolicy` is pure:

| Situation | Delay |
| --- | --- |
| An agent is running | The user's interval (30s to 5m) |
| Everything has settled | max(interval, 2m) |
| No open PRs | max(interval, 5m) |
| Low Data Mode or an expensive network | At least 5m |
| Failure | 30s, 60s, 120s … capped at 10m |
| Rate limited, or fewer than 250 points left | Until the reset, plus 5s |

`Monitor` also refreshes immediately 2s after wake, when the network returns, when the panel opens with data older than 30s, and on ⌘R. Refresh requests during a poll are coalesced into one follow-up poll.

## Concurrency

Swift 6 language mode with complete checking and no `@unchecked Sendable`:

- UI-facing models are `@MainActor @Observable`.
- `PullRequestFetcher` is an `actor` that owns the detail cache, so JSON decoding happens off the main thread.
- `GitHubClient` is a `Sendable` value holding its token. It's rebuilt when the token changes, which replaces the 0.x pattern of a closure reaching into main-actor state from background tasks.
- Networking uses typed throws (`throws(GitHubError)`), so every failure mode is an exhaustive `switch` for the caller.

## UI and design decisions

**MenuBarExtra (`.window`) over NSStatusItem + NSPopover.** The system provides the Liquid Glass panel, positioning, dismissal and accessibility. What's given up, programmatic open/close and status-item access, isn't needed: notifications open the PR directly. This removed about 150 lines of AppKit sizing code, including five `PreferenceKey`s and manual height arithmetic.

**No glass on glass.** Apple's guidance is that Liquid Glass is the functional layer and content should sit beneath it, without layering glass on glass. The panel is already glass, so everything inside uses plain fills: rows behave like menu items with an instant hover highlight, and icon buttons use a circular hover fill with a 0.96 press scale.

**Template menu bar icon by default.** The HIG asks menu bar extras to use template images that the system tints. State is carried by the badge's *shape*: a filled dot means "act on this", a ring means "in progress", and a dimmed glyph means "not connected". It never relies on color. Colored badges are an opt-in setting. The glyph is a custom-drawn pull request mark (`PullRequestMark`), because the closest SF Symbol reads as a generic merge arrow at 16pt.

**Rows are two light lines.** The title, then the number, author and age, led in color only by what the status glyph can't express: which agent failed, how many threads, progress ("2 of 4"), or "Approved". A ready PR shows no status words at all, because the glyph already says it. VoiceOver still gets the full wording. Status glyphs are palette-rendered SF Symbols (the glyph in the status color on a tinted disc), not solid badges. Per-agent detail lives behind the disclosure chevron.

**Filters, not segmented controls.** Scope and draft filtering sit in a menu behind a filter button that fills in when a filter is active, the pattern used by Mail and Files.

**Skeletons, not spinners.** First load, the repository picker, sign-in verification and avatars all show "bones" that mirror the geometry of the real content, so nothing shifts when data arrives. They pulse gently (static under Reduce Motion) and crossfade to content in 200ms.

**Settings uses a sidebar.** The window is a `NavigationSplitView`: the account on top (like System Settings' Apple Account row), then evenly spaced rows. Add actions are a small "+" at the trailing edge of their section header, and the agent mode is an iOS-style checkmark list. Rows are drawn by hand only to get a neutral selection: a soft gray pill with primary text, where a system `List` would use the accent color. Glyphs take their label's font in a fixed-width column, hover is an instant faint wash, rows scale with the user's Sidebar Icon Size setting, and the arrow keys move the selection. While Settings is open, the app joins the Dock and ⌘-Tab, and leaves when the window closes.

**The app icon is a layered Liquid Glass icon.** `PRMonitorApp/AppIcon.icon` is an Icon Composer document with three glass groups (branches, nodes, and an attention dot) at different depths, individual specular lighting, and separate light and dark gradient fills. It targets shared "squares", so the same source compiles for iOS, iPadOS and macOS; `actool` emits Light, Dark and Tintable renditions.

**Hierarchy through restraint.** Color is reserved for the status phrase and glyph, so in a list of 20 PRs the eye lands on the red and orange lines that need action.

**Typography and geometry** follow the macOS text styles: Headline 13pt bold for the title, Body 13pt for PR titles, Subheadline 11pt for metadata. Highlights sit 5pt inside the panel edge and text 14pt in, matching native menus. Corner radii are concentric (`ConcentricRectangle` against the panel's container shape).

**Motion** is short and never bounces:
- Disclosure is an interruptible `.smooth(duration: 0.25)` spring. The expanded list enters with a fade and a 4pt drop, and exits in 150ms with a fade and a 4px blur, because exits should be quicker and softer than enters.
- Hover never animates, since it happens dozens of times a day. Icon buttons scale to 0.96 when pressed.
- Status glyphs change with `.contentTransition(.symbolEffect(.replace))` and counts with `.numericText()`.
- Only first-run onboarding uses a staggered entrance (80ms per chunk), because it's rare.
- With Reduce Motion enabled, movement is removed and opacity fades remain.

## Testing

`swift test` runs 39 Swift Testing tests in about 10ms, with no network access:

- `StatusEngineTests`: grouping, precedence and each accuracy edge case above.
- `NotificationPlannerTests`: baseline, once per SHA, new pushes, regressions, preferences, identifier stability.
- `PollingPolicyTests`: intervals, backoff and rate-limit waits.
- `GraphQLDecodingTests`: payloads shaped like live responses (anonymized), partial errors, `null` nodes, domain mapping.
- `SettingsMigrationTests`: 0.x to 1.0 migration and round-tripping.
- `RepositoryIDTests`: every common way of writing a repository, including pasted URLs.

## Prior art

Before the rewrite I studied Trailer, Gitify, CCMenu2, gh-dash, supacode and Pullfather. From them PR Monitor borrows:
- gh-dash's cheap-list / rich-detail split;
- Pullfather's single async scheduling loop and handling of `gh` paths;
- CCMenu2's first-poll-is-a-baseline rule;
- supacode's lesson that small alias chunks avoid 504s on busy repositories.

It avoids Trailer's missing `CheckRun.status`, which renders running checks as neutral, and Gitify's discard-the-batch-on-any-error behavior.
