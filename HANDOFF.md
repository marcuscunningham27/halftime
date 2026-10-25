# Halftime (sports app): handoff

Native macOS sports app called **Halftime** (SwiftUI, macOS 26, Swift 6, Liquid Glass), modelled on Apple's iOS Sports app and ESPN.
The original brief is `Mac Sports App — Claude Code Spec.md`. Last updated 21 October 2026.

## Goal

A menu-bar-plus-window sports app with live scores, smart notifications, rich game pages, a Fantasy section
(Sleeper and ESPN Fantasy) and optional AI features (Apple's on-device model or Claude). The user works in
small rounds: they send screenshots and requests, and each change is built, checked in the running app,
then reported back.

## Current progress

All 8 phases of the spec are done, plus a lot of extra design work.

- **Scores:** ESPN's unofficial site API covers NFL, college football (AP Top 25 only: its Standings tab is the poll, so search offers only ranked teams), NBA, WNBA, MLB, NHL, EPL, Champions League and MLS (soccer leagues share the EPL code; WNBA reuses all the NBA code; AFL and NRL were dropped in Oct 2026: ESPN's data for them was too thin). There's a Home tab
  (Yesterday/Today/Upcoming, My Teams first), and league and team pages with the same picker, recent
  results and standings.
- **Where to watch:** score cards (Home, league pages) show a glass pill under the status with up to two
  channels/apps for live and upcoming games (`Game.broadcasts`, from the scoreboard's `geoBroadcasts`,
  national first, falling back to `broadcasts`). Hover shows the full list.
- **Menu bar:** a live score label, a popover, 15-second polling, a Close to Menu setting and launch at login.
- **Following:** follow teams and leagues (SwiftData). The sidebar has a search field under Home and a
  hairline between followed leagues and teams.
- **Notifications:** an event detector, preferences that resolve team over league over global, quiet hours,
  and red zone alerts. An optional "Describe scoring plays in alerts" setting writes a one-line play
  description with the on-device model only (never Claude). It retries ESPN's play-by-play for about
  25 seconds, matching the play by score.
- **Game page:**
  - A playing surface for each sport:
    - NFL field in ESPN style, with Down / Ball On / Drive header, goalposts, end zones, the drive, and the last play.
    - Gamecast (`DesignSystem/Gamecast.swift`, NBA, NFL, NHL and MLB): `GamecastView` wraps the surface with a last
      play banner (Timeout / End of 1st / End of Game too), timeouts (and NBA fouls/bonus), and the 3 latest
      plays. NFL: home logo at midfield, ball slides and pulses; NFL timeouts are filed under the drive's
      team by ESPN, so the caller is read from "Timeout #1 by SF". NBA: last play banner over the court, the home logo at centre court,
      the team in possession's half shaded with moving chevrons, a pulse on the latest shot, timeouts left
      (pips), team fouls and BONUS, then the 3 latest plays. The line score sits between the teams under the
      clock (all four). NHL: home logo at centre ice, pulse on the latest shot, POWER PLAY · team and
      EMPTY NET pills (core API `powerPlay`/`emptyNet`; the team is the one the latest "X against Y" penalty
      wasn't filed under). MLB: the banner follows every pitch; the list shows "Play Result" at-bats, whose
      headline ("Single", "Fly Out") is copied from the pitch put in play when parsing. The diamond's arc
      is the latest at-bat only (none after a strikeout or walk); ESPN puts the hit spot on either the
      result row or the "Ball In Play" pitch, so `atBats` checks both. The header line score is `compact`. Possession is inferred from plays (`CourtSituation.possession`); timeouts and
      fouls come from ESPN's core API `.../competitions/{id}/situation`, fetched only while live.
    - MLB diamond, NHL rink and soccer pitch.
  - A line score, then Overview, Stats, Play-By-Play and Box Score tabs.
  - Win and cover probability charts with hover values.
  - Recap / Catch Me Up card with no AI needed: finished games show ESPN's written story
    (`GameOverview.recap`, parsed from the summary's `article`); live games, and finals without a story, show
    `GameFacts.summary` (score, top performers, NBA runs or the latest score, NFL/MLB situation, deciding
    period). "Summarise with Claude/AI" rewrites it with the chosen engine when that engine can run.
  - Ask About the Game: four one-click `QuickQuestion`s per league (SportsKit), answered from the stats by
    `GameFacts.answer` (leaders, team stats, scoring plays, runs, drives, box rows); `.model` questions and typed
    questions go to the AI engine, except typed questions `GameFacts.answer(typed:)` can answer from the stats:
    a named player ("how many rebounds does Booker have?", matched on surname, reads their box score row) or a
    leader category ("most points"). The on-device model gets `compact` prompts (latest 10
    scoring plays) because a full NBA game overflowed its ~4,000-token context; it still invents players now and then. The typed box only shows when an engine is available. The user found the
    on-device model too error-prone for free-written summaries, hence this.
- **Widgets:** My Teams (each team's live game, else a result from the last 36 h, else its next game;
  rows ordered live, results, upcoming) and League, with an App Group for shared data and Chakra Petch scores.
- **AI** (Settings › Summaries): pick On-Device (Apple Foundation Models, the default) or Claude
  (`claude-haiku-5-5`, key stored in the Keychain).
- **Fantasy** (sidebar under Home): saved leagues in Settings › Fantasy (Sleeper by username, ESPN by league
  ID plus optional espn_s2 and SWID cookies). The toolbar's league dropdown switches between them. Five tabs:
  - **Lineup:**
    - A matchup card: actual points in big type, PROJ beneath, and a win chance bar.
    - A Week Briefing (AI, only when the user clicks "Brief Me"), then linked news stories.
    - Starters and bench with status, bye week, news, and Proj and last-week columns.
  - **Past Week:** a week picker, games, and your players' ESPN stat lines and points.
  - **Upcoming:** next week's games, with dates.
  - **Season:** trend tiles, a projected-vs-actual chart with hover, gaps by position and by starter, and
    standings (your row is a green glass capsule).
  - **News:**
    - A roster summary.
    - A Bye Weeks card with traffic lights (Clear, Covered, Hole) and Who's Missing and Covered By columns.
    - An injury report and the latest news (ESPN/Rotowire, clickable).

Tests: 132 passing in SportsKit.

## Name and icon

- Shown everywhere as **Halftime** (display name, `PRODUCT_NAME = Halftime`, so the built app is `Halftime.app`).
  The bundle IDs (`com.marcuscunningham.SportsApp`, `.Widgets`), App Group, Keychain services, Xcode target,
  scheme and Swift module (`PRODUCT_MODULE_NAME = SportsApp`) keep the old name on purpose, so saved settings,
  follows and fantasy leagues carry over.
- Icon (`SportsApp/AppIcon.icon`): a halfway line, centre circle and spot in white over a green left half and
  blue right half (`background.png`, glass translucency off so the colours stay rich). The layers are drawn
  by a small CoreGraphics script; macOS caches icons, so an old icon can linger in the Dock until it restarts.
- Home's toolbar shows a "Halftime" wordmark with `HalftimeMark` (the icon's markings on a clear glass tile,
  in `HomeView.swift`) instead of the plain "Home" title.

## Layout and key files

- `SportsKit/` (local Swift package): models, providers and logic. Logic is kept here so it can be unit-tested.
  - `Providers/ESPN/ESPNProvider.swift` and `ESPNEndpoints.swift` hold every ESPN path, `nflWeek` (one week
    in one request) and `nflByes`.
  - `Providers/Sleeper.swift`: users, leagues, rosters, lineup slots, players (cached on disk for 3 hours as
    `sleeper-players-v3.json`), projections scored with the league's own `scoring_settings` (matches Sleeper
    exactly), matchups, standings and the calendar.
  - `Fantasy/Fantasy.swift`: the shared `FantasyPlayer`, `FantasyTeam`, `FantasyMatchup` (including
    `winProbability`) and `FantasyLeagueRef` types, and `FantasyData`, which dispatches to each provider.
  - `Fantasy/ESPNFantasy.swift`: the ESPN Fantasy league API.
  - `Fantasy/FantasyInsights.swift`: `SeasonTrend`, `FantasyStanding`, `ByeWeekPlanner` and `LineupCover`
    (who fills each slot, using a matching algorithm), `ESPNNews` (news feed and roster ID lookup), and
    `FantasyPrompt` (the weekly briefing prompt).
  - `Claude/ClaudeService.swift`: raw-HTTP Messages API calls, `GamePrompt` (recap, catch-up, play line, ask).
  - `Engine/Probability.swift`: chart maths.
- `SportsApp/`:
  - `App/ContentView.swift`: the sidebar, search, and `popToRoot`. Clicking a row again sends its page back
    to the top; Fantasy also returns to Lineup.
  - `DesignSystem/`: `ScoreStyle` (score font, ScoreCard, SportsCard, Backdrop with `.backdrop(color)`),
    `GlassPicker`, `PlaySurfaces`, `FieldView`, `UnitSystem`.
  - `Features/Fantasy/`: `FantasyView`, `FantasySeasonView`, `FantasyNewsView`, `WeekOverviewCard`,
    `FantasyStore` (saved leagues, plus ESPN cookies in the Keychain), `FantasySettings`.
  - `Features/Claude/`: `RecapEngine` (picks on-device or Claude), `ClaudeKey` (Keychain), `RecapCard`, `AskCard`.
  - `Features/Notifications/`: `NotificationService` and `SettingsView` (General, Notifications, Following,
    Fantasy and Summaries tabs).
- `SportsWidgets/SportsWidgets.swift`.

## Build and run

- `xcodebuild -project SportsApp.xcodeproj -scheme SportsApp -configuration Debug -allowProvisioningUpdates build`,
  then open `~/Library/Developer/Xcode/DerivedData/SportsApp-blqwxhtuufmkyjhcpilwreraremh/Build/Products/Debug/Halftime.app`.
  Run `pkill -x Halftime` first, or `open` just brings the old build forward.
- Run tests outside ~/Documents (codesign fails on extended attributes):
  `cd SportsKit && swift test --scratch-path <scratchpad>/skbuild`.
- Widgets: bump `CURRENT_PROJECT_VERSION` (currently 48) and run `lsregister -f` on the app whenever widget
  code **or SportsKit** changes (the widget links SportsKit). Otherwise widgets draw grey placeholders and
  chronod logs "Bundle version did not match". `killall chronod` makes them reload straight away.
- The user checks things visually. Check changes in the running app (the computer-use tools work; macOS
  won't open pop-up menus in the background, and nothing can be clicked while the screen is locked).

## What worked

- Keeping all parsing and logic in SportsKit with small fixture or inline-JSON tests, and only UI in the app.
- ESPN team rosters, matched by name within the player's own team, cover players Sleeper has no ESPN ID for.
  Sleeper's photo CDN (`sleepercdn.com/content/nfl/players/thumb/{id}.jpg`) covers every player.
- ESPN's fantasy news feed: `site.api.espn.com/apis/fantasy/v2/games/ffl/news/players?playerId=` (Rotowire,
  with links).
- Precomputing facts for the AI (lineup issues, eligible bench cover) instead of asking the small on-device
  model to reason them out. It got them wrong otherwise.
- Separating a sidebar section with a line drawn from the List via `anchorPreference`. Rows clip their own
  overlays, and macOS keeps rows a fixed height.

## What didn't work

- `toolbarTitleMenu` inside a split-view NavigationStack shows no menu. The Fantasy league dropdown uses a
  `ToolbarItem(.navigation)` Menu instead, with the title removed.
- `contentMargins` doesn't apply to the sidebar List; padding does.
- Divider rows and section headers as separators in the sidebar (they leave big gaps or get covered by the
  selection highlight).
- `claude-haiku-5-5` with `max_tokens: 400` returned empty answers, because thinking is on by default and
  counts against the cap. The fix is `max_tokens: 4000` plus `output_config.effort: "low"`, and handling a
  `max_tokens` or `refusal` stop reason.
- ESPN NBA clocks drop to plain seconds ("45.3") in a period's last minute, which broke the probability
  chart. Both formats are now parsed.
- Yahoo Fantasy can't be done without a registered Yahoo developer app (OAuth). It's shown as unavailable.

## Next steps / open items

- ESPN Fantasy is tested against sample JSON only. It needs a real league to confirm parsing and lineup
  slots.
- Rich score alerts haven't been seen on a live score since the retry fix.
- The widget three-digit score fix hasn't been checked on the desktop.
- Possible extras the user mentioned or that came up: weather in lineup notes, injury return dates from
  news instead of status-based guesses (Out = 1 week, IR = 4), and a win chance that moves with live points.
- NBA and NFL Gamecasts checked live by the user (22 Oct 2026). NHL and MLB were built on finished
  games only; the power play pill and the pitch-by-pitch banner still need a live look.
- Fantasy stars (NFL games only): `FantasyStore.loadRoster()` loads every saved league's team (cached 10 min);
  `FantasyRoster` (SportsKit) matches play text by full or ESPN short name ("J.Daniels") and box rows by ESPN
  ID or name. Starred + yellow tint in the game cast, Play-by-Play and Box Score.
