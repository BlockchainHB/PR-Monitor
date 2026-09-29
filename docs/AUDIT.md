# 0.x Audit

This audit of PR Monitor 0.1 (commit `baf7fdb`) motivated the 1.0 rewrite. Findings are grouped by area and ordered by user impact. Each links to where 1.0 addresses it.

## Accuracy

| Severity | Finding | Impact | Fix in 1.0 |
| --- | --- | --- | --- |
| **High** | Configured agents with no check on a PR stayed `notFound`, which counted as **Waiting forever**. Every user started with Vercel, Cursor and Devin seeded. | Any repo without all three showed "Waiting" permanently, and "all agents complete" never fired | Agents that haven't reported are hidden after a 3-minute startup grace period (`StatusEngine`) |
| **High** | Only check runs were read. **Commit statuses** (the Vercel, Netlify and CodeRabbit style) were ignored. | Deploy integrations were invisible or permanently "No check yet" | The GraphQL `statusCheckRollup` covers both check runs and statuses |
| **High** | When a pattern matched several checks, only the **latest** was considered | A failed `build` job could be hidden by a later passing `lint` job | All matching checks are aggregated: any failure fails, any pending is pending |
| **Medium** | "Needs review" meant *any comment since the check started*, including the bot's own status comments | Vercel's deploy comment made PRs look like they needed review | Feedback is **unresolved, non-outdated review threads** or *changes requested* |
| **Medium** | The PR pill said "Waiting" while its agent row said "Needs review" for the same state | Contradictory UI | One state model (`AgentReport.State`) drives both |
| **Medium** | Review-only bots (Copilot, Codex) were never detected as running | PRs looked finished while a bot was still reviewing | Pending review requests mean "reviewing", and reviews are tied to commit SHAs |
| **Low** | Workflows awaiting approval were invisible | A fork PR looked green while blocked | Surfaced from `checkSuites` as "Action required" |

## Notifications

| Severity | Finding | Fix in 1.0 |
| --- | --- | --- |
| **High** | On **every launch**, each finished PR and each done agent fired a notification, because the "last seen" dictionaries started empty | The first poll records a baseline and posts nothing |
| **High** | The review-summary dedupe key included `updatedAt`, so any comment, label or reviewer change re-notified | Lifecycles are keyed by head commit SHA |
| **Medium** | "All agents complete" was global across every PR, and its settings toggle was a disabled switch that did nothing | A per-PR "settled" notification, with real toggles |
| **Medium** | Clicking a notification did nothing | Clicking opens the PR, and notifications are grouped by PR |
| **Low** | Permission was requested at launch, before the user had seen any value | Requested in context |

## Architecture and correctness

| Severity | Finding | Fix in 1.0 |
| --- | --- | --- |
| **High** | `@Published` publishes on `willSet`, so the Combine sinks restarted polling with the **old** value. After sign-in, `isSignedIn` was still `false`, so the timer was torn down and **polling never started** until a manual refresh. Toggling a repo refreshed with the previous repo list. | The `Observations` sequence delivers post-change values, and there's one scheduling loop |
| **High** | About 5 REST calls per PR per poll (PR list, check runs, 3 comment endpoints), plus a `/user` call every poll | Two-phase GraphQL at ~1 point per repository ([ARCHITECTURE.md](ARCHITECTURE.md#fetching-two-phases-one-request-per-ten-repositories)) |
| **High** | One inaccessible repository failed the **whole refresh**, because the throwing task group failed on the first error | Per-repository results, keeping last good data |
| **Medium** | Init triggered 4 refreshes, since each sink fires on subscribe, each cancelling the last | One loop with coalesced refreshes |
| **Medium** | A revoked token showed "HTTP 401" forever | 401 signs out with a clear "session expired" message |
| **Medium** | Main-actor `AuthStore.token` was read from background tasks through a closure (a data race hidden by Swift 5 mode) | Swift 6 strict concurrency, with a `Sendable` client holding its token |
| **Medium** | No handling for sleep/wake, network loss, or GraphQL secondary rate limits | `SystemEvents`, `PollingPolicy`, and `Retry-After` support |
| **Low** | Device-flow form bodies weren't percent-encoded, and sign-in couldn't be cancelled | `URLComponents` encoding, and a cancellable task |
| **Low** | Settings saved on every property set during load, and a decode failure silently wrote defaults | Versioned document, no saves while loading, migration from 0.x |
| **Low** | The Xcode project listed files by hand and was already out of sync with SwiftPM | Xcode 16+ synchronized folders, plus a unit-test target |

## Onboarding

| Severity | Finding | Fix in 1.0 |
| --- | --- | --- |
| **High** | Signing in required creating your own GitHub OAuth app and pasting its client ID, before anything worked | One-click **GitHub CLI** sign-in, a personal access token, or device flow with a build-time client ID |
| **Medium** | Adding repositories meant typing `owner/name`, with a separate five-section browse form | A searchable picker that also accepts pasted URLs |
| **Medium** | Agents had to be configured by hand, with inline edit forms | Automatic mode by default; custom mode with presets and "seen on your PRs" suggestions |

## Design (HIG)

| Severity | Before | After | Why |
| --- | --- | --- | --- |
| **Medium** | Material cards inside `GroupBox`es inside a popover | Flat, menu-like rows inside the system glass panel | Nested containers; content shouldn't carry its own glass or material |
| **Medium** | 520pt-wide popover with manual height math (5 `PreferenceKey`s) | 360pt `MenuBarExtra` window sized to content | Menu bar panels are narrow; let the system size and place them |
| **Medium** | Colored dot rendered by an `NSHostingView` inside the status button | Template image, with state carried by badge shape | The HIG asks for template images, and the hosted view broke button semantics |
| **Medium** | Every status shown with equal visual weight | Solid wells only for failing and needs review | Hierarchy: attention goes to what needs action |
| **Low** | A pointing-hand cursor pushed on hover over whole cards | Standard arrow cursor with a hover highlight | macOS uses the pointing hand for links only |
| **Low** | "2 hrs ago", "Signed in as …" and a wordy footer | Compact ages ("2h"); secondary information moved to tooltips | Density suited to a glanceable surface |
| **Low** | Section headers in caption size and weight, mixed type sizes | macOS text styles: Headline, Body, Subheadline | Consistent type ramp |
| **Low** | 150ms animation on every hover | Instant hover; 0.25s smooth disclosure; opacity-only with Reduce Motion | High-frequency interactions shouldn't animate |

## Testing

0.x had two smoke tests (a string concatenation and enum raw values). 1.0 has 39 behavioral tests covering status derivation, notification planning, polling, decoding and migration. It also has a `--diagnose` tool for checking results against live repositories.
