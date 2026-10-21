# Mac Sports App — Claude Code Spec

Oct 20, 2026 · @Marcus Cunningham

## Overview

A native macOS sports app, in the spirit of Apple's iPhone Sports app, that lives in the menu bar and delivers live scores and smart notifications for the teams and leagues you follow. It is built in SwiftUI with a Liquid Glass look, and Claude features come in a later phase.

**Goals**

- Live scores and a full scoreboard one click away, from the menu bar.
- Follow teams and leagues; notifications switch on automatically for anything followed.
- Fine-grained, per-event notification toggles (game start, quarter end, score updates, NFL red zone, final).
- Feels like a first-party Apple app: native controls, SF Symbols, system fonts, Liquid Glass materials.

**Non-goals (v1)**

- Licensed data feeds, betting, video, or streaming.
- App Store distribution (build and run locally first).
- iOS or tvOS targets. Keep the data layer in a shared Swift package so they can be added later.

**Targets and tooling**

- macOS 26 (Tahoe) minimum, so Liquid Glass APIs are available without fallbacks.
- Swift 6, SwiftUI, Swift Concurrency, SwiftData for persistence, UserNotifications for alerts, WidgetKit for widgets.
- Xcode project plus a local Swift package (`SportsKit`) for models and data.

## Design principles

When in doubt, do what a first-party Apple app would do, and follow the iOS Sports app's patterns before inventing new ones.

**Native first**

- Standard SwiftUI controls only: `NavigationSplitView`, `List`, `Toggle`, `Picker`, `Form`, `Settings` scene. No custom chrome where a system control exists.
- SF Pro and SF Symbols throughout, Dynamic Type-friendly text styles, system accent colour.
- Respect system settings: light/dark, reduced motion, reduced transparency, increased contrast, Focus modes.
- Standard Mac behaviours: keyboard shortcuts, menu bar commands, Spotlight-friendly window titles, Settings via Cmd+comma.

**Liquid Glass**

- Use the system Liquid Glass materials and APIs (`glassEffect`, `GlassEffectContainer`, glass button styles) for toolbars, floating controls, the menu bar popover, and score cards. Do not hand-roll blur.
- Content sits on a plain background; glass is for controls and floating layers, so scores stay readable.
- Team colours are used sparingly as accents behind or inside cards, as the iOS Sports app does.
- Keep corner radii, spacing, and concentricity consistent with system components.

**Cues to borrow from the iOS Sports app**

- Games grouped by league, with live games on top, then upcoming, then final.
- Compact score row: both team logos, abbreviations, scores, and a clock or start time on the right.
- Tapping a game opens a detail view with a header scoreboard, then tabs for plays, box score, and team stats.
- A Following section at the top, then league browsing below.
- Live indicators and a Live Activity-style compact view, which maps to the menu bar item on Mac.

## Core features (MVP)

1. **Menu bar item.** A `MenuBarExtra` (window style) showing a compact live score for the pinned game, for example `KC 21 – 17 BUF · Q3`. It falls back to a sports icon when nothing is live. Clicking opens a glass popover with live and upcoming games for followed teams, plus an Open Sports button.
2. **Main window.** `NavigationSplitView` with a sidebar (Following, Today, then leagues) and a scoreboard in the detail pane. Date picker to browse other days.
3. **Game detail.** Header scoreboard, live clock, and period-by-period scores, then Plays, Box Score, and Team Stats tabs. Auto-refreshes while the game is live.
4. **Leagues in v1.** NFL, NBA, MLB, NHL, English Premier League, plus AFL and NRL if a usable free source exists (see Data layer). Adding a league should only require a new provider mapping.
5. **Follow teams and leagues.** Star button on teams and leagues. Followed items appear in the Following section and drive notifications (next section).
6. **Settings window.** Tabs for General (launch at login, menu bar display style, time zone), Following, Notifications, and Data.
7. **Widgets (after MVP).** Small and medium WidgetKit widgets for a followed team's next or live game.
8. **Global hotkey (after MVP).** Configurable shortcut to toggle the scoreboard popover from anywhere.

## Favourites and notifications

Following a team or league turns its notifications on automatically, with sensible defaults. Every event type can then be toggled, globally or per team and league.

**Rules**

- Following a league enables the default event set for every game in that league. Following a team enables the default set for that team's games only.
- Team settings override league settings, which override global defaults. A team can be muted without unfollowing it.
- Unfollowing removes its notification overrides. Re-following starts from the defaults again.
- On first follow, request notification permission through `UNUserNotificationCenter`. If denied, show an inline banner in Settings that links to System Settings.
- Respect Focus modes and use time-sensitive interruption level only for opt-in events (for example final score).
- A quiet hours option (off by default) holds non-urgent alerts.

**Notification events**

| Event | Applies to | Default on |
| --- | --- | --- |
| Game start / kickoff | All sports | Yes |
| Score updates | All sports | Yes |
| Period or quarter end | NFL, NBA, NHL, others with periods | No |
| Halftime | NFL, NBA, soccer, others | No |
| Final score | All sports | Yes |
| Red zone | NFL only | No |
| Close game, final minutes | NFL, NBA, NHL | No |
| Overtime or extra time | All sports | Yes |
| Lead changes | All sports | No |

**NFL red zone alert**

Fires when the team with possession first reaches the opponent's 20-yard line or closer (goal-to-go included) on a play, once per drive. It is derived from the play-by-play feed (yard line plus possession), not from the score. It de-duplicates per drive, and repeated entries on the same drive do not re-notify. Body text: team, yard line, down and distance, for example `Chiefs in the red zone: 1st and 10 at BUF 18`.

**Data model (SwiftData)**

- `FollowedTeam` (teamID, leagueID, createdAt)
- `FollowedLeague` (leagueID, createdAt)
- `NotificationPreference` (scope: global, league, or team; scopeID; eventType; isEnabled)
- `NotificationLog` (gameID, eventKey, firedAt) for de-duplication across polls and restarts

**Delivery**

The app polls while running and fires local notifications from detected state changes (diff the previous and current game snapshot). Local notifications only work while the app is running, so v1 should launch at login by default and stay in the menu bar. Push notifications while the app is quit would need a server component, so treat that as a possible later phase.

## Data layer

All sports data goes through one protocol, so sources can be swapped or mixed per league without touching the UI.

```swift
protocol SportsProvider {
    func leagues() async throws -> [League]
    func scoreboard(league: League, date: Date) async throws -> [Game]
    func gameDetail(id: Game.ID) async throws -> GameDetail
    func plays(id: Game.ID) async throws -> [Play]   // needed for red zone
}
```

**Providers**

| Provider | Use for | Notes |
| --- | --- | --- |
| ESPN unofficial endpoints | NFL, NBA, MLB, NHL, soccer, college | Free, undocumented, can change without notice. Fine for personal use. Primary source in v1. |
| TheSportsDB or API-Sports | Gap-filling, including AFL and NRL | Free tiers are rate-limited; check coverage before committing. |
| Sleeper API | Fantasy overlay (later) | Free and documented. |

Check AFL and NRL coverage and latency early, since the app is being built in Brisbane. If free sources are too slow or patchy for those leagues, ship v1 with the US leagues and soccer first.

**Polling and caching**

- Poll every 15 seconds for games in progress, every 5 minutes for today's scheduled games, and not at all for finished games more than a day old.
- Poll only leagues that are followed or currently on screen. Back off on errors (exponential, capped at 2 minutes) and use conditional requests where supported.
- Pause polling on sleep and resume on wake. Cache the last good snapshot in SwiftData so the menu bar renders instantly on launch.
- Normalise every provider into shared models: `League`, `Team`, `Game` (status, period, clock, score, start time), `Play`, `BoxScore`. UI and notification code never see provider types.
- Isolate network and parsing in an actor. Keep unofficial endpoint paths in one file with tests against saved JSON fixtures, so breakage is easy to find and fix.

**Change detection**

A `GameEventDetector` compares the previous and new `Game` snapshots and emits typed events (`gameStarted`, `scoreChanged`, `periodEnded`, `redZoneEntered`, `final`, and so on). Notifications subscribe to this stream, so adding an event type means adding one detector rule and one toggle.

## Architecture and project structure

A thin SwiftUI app on top of a Swift package that owns models, providers, and event detection. The UI reads observable state, and notifications are driven by the event stream, not by views.

```
SportsApp/
  SportsKit/               (local Swift package, no UI)
    Models/                League, Team, Game, Play, BoxScore
    Providers/             SportsProvider, ESPNProvider, SportsDBProvider
    Engine/                PollingScheduler, GameEventDetector
    Persistence/           SwiftData models, snapshot cache
  SportsApp/
    App/                   @main, scenes, MenuBarExtra, Settings
    Features/
      MenuBar/             compact score label, popover
      Scoreboard/          sidebar, game list, game row
      GameDetail/          header, plays, box score, stats
      Following/           follow buttons, followed list
      Notifications/       NotificationService, preference UI
    DesignSystem/          glass components, team colour helpers
  SportsWidgets/           WidgetKit extension (later)
  Tests/                   fixtures, detector tests, preference resolution tests
```

**Conventions**

- `@Observable` view models, `async/await` only, no Combine unless needed.
- All provider JSON decoding is covered by fixture tests; all event detection rules are covered by snapshot-diff tests (including red zone de-duplication).
- Notification preference resolution (team over league over global) is a pure function with its own unit tests.
- App Sandbox on, with only the outgoing network entitlement. Hardened runtime on.
- No secrets in the repo; API keys (if any) go in the Keychain or an untracked config file.

## Claude features (later phase)

Add these only after the MVP and notifications are solid. Each one should be a small, optional feature that fits the native UI, never a chat panel bolted on.

1. **Game recap.** A Summarise button on a finished or in-progress game that turns the play-by-play and box score into a short recap. Cheapest and most natural first feature.
2. **Catch me up.** For a live game you joined late: two or three sentences on what has happened so far, and what to watch for.
3. **Notification wording.** Optional richer alert text, such as a one-line description of the play that caused a score change. Off by default, since it adds latency and cost.
4. **Ask about the game.** A small text field in game detail for questions grounded in that game's data ("who has the most rushing yards?").
5. **Fantasy insights (with the Sleeper overlay).** Plain-language notes on a matchup, built from live scores plus roster data.

**Implementation notes**

- Call the Anthropic API from a single `ClaudeService`, with the API key stored in the Keychain and entered in Settings. Use a small, fast model for recaps and alerts.
- Always ground prompts in structured game data from `SportsKit` and instruct the model not to invent stats. Show a subtle "AI-generated" label.
- Features are fully hidden when no key is set. The app must work completely without them.

## Build phases and kickoff prompt

| Phase | Scope | Done when |
| --- | --- | --- |
| 1. Foundation | Xcode project, `SportsKit` package, models, ESPN provider for NFL, fixture tests | Scoreboard JSON decodes into `Game` models in tests |
| 2. Scoreboard UI | Main window, sidebar, game rows, Liquid Glass styling, game detail | Browse any date and open a game |
| 3. Menu bar | `MenuBarExtra`, live label, popover, polling scheduler | Live score updates in the menu bar every 15 seconds |
| 4. Following | Follow teams and leagues, Following section, persistence | Follows survive relaunch |
| 5. Notifications | Event detector, preference model, Settings UI, red zone | Each toggle fires or silences its event in tests and on a live game |
| 6. More leagues | NBA, MLB, NHL, soccer, then AFL and NRL if feasible | New league is a provider mapping only |
| 7. Polish | Widgets, global hotkey, launch at login, accessibility pass | Works with reduced transparency and VoiceOver |
| 8. Claude | Recaps first, then the rest of the later list | Everything hidden with no API key |

**Kickoff prompt for Claude Code**

```
Build a native macOS sports app in SwiftUI (macOS 26, Swift 6) following SPEC.md in this repo.
Start with Phase 1 only: create the Xcode project and a local Swift package called SportsKit
with the shared models, a SportsProvider protocol, and an ESPN provider for NFL scoreboards.
Add fixture-based decoding tests using saved JSON. Use standard SwiftUI controls and the
system Liquid Glass APIs, and follow Apple Human Interface Guidelines and the iOS Sports app
for layout cues. Do not build UI beyond a minimal scoreboard list yet. When Phase 1 passes
its tests, stop and summarise what was built before moving to Phase 2.
```

Paste this whole doc into `SPEC.md` (export it as Markdown) in the project root, and work one phase at a time, reviewing each before moving on.
