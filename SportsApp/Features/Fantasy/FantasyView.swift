import SportsKit
import SwiftUI

/// Your fantasy team in the league picked from the title menu, in three tabs like Home's day picker:
/// the current lineup, a played week's games with your players' stats (ESPN box scores) and points,
/// and next week's games. Works the same for every provider through `FantasyData`.
struct FantasyView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case lineup = "Lineup", past = "Past Games", upcoming = "Upcoming", season = "Season", news = "News"
        var id: Self { self }
    }

    struct Entry: Identifiable {
        let game: Game
        let players: [Line]
        var id: Game.ID { game.id }
    }

    struct Line: Identifiable {
        let player: FantasyPlayer
        let isStarter: Bool
        let points: Double?
        let stats: [String]
        /// The provider's ESPN ID, or else one found by name in the box score.
        let espnID: String?
        var id: String { player.id }
    }

    /// Lineup and upcoming games for the selected league, loaded together.
    struct Base {
        let league: FantasyLeagueRef
        let state: Sleeper.State
        let team: FantasyTeam
        /// The latest week with games under way or played.
        let latestWeek: Int
        let upcomingWeek: Int
        let upcoming: [Entry]
        /// This week's head-to-head (the upcoming week's), with projections for it and points from the week before.
        let matchup: FantasyMatchup?
        let projections: [String: Double]
        let lastWeekPoints: [String: Double]
        /// Roster planning: league calendar, each NFL team's bye week, and news per player.
        let calendar: FantasyCalendar?
        let byes: [String: Int]
        let news: [String: [PlayerNews]]
        /// ESPN IDs found by name for players the provider didn't link, for photos and news.
        let espnIDs: [String: String]

        func espnID(_ player: FantasyPlayer) -> String? { player.espnID ?? espnIDs[player.id] }
    }

    /// Season tab data: every completed week's starters, and the standings.
    struct Season {
        let trend: SeasonTrend
        let standings: [FantasyStanding]
    }

    let provider: any SportsProvider

    @State private var tab = Tab.lineup
    @State private var base: Base?
    /// The played week on show; nil follows the latest.
    @State private var chosenWeek: Int?
    @State private var past: (week: Int, entries: [Entry])?
    @State private var season: Season?
    /// The week briefing, kept here so switching tabs doesn't rewrite it; cleared on each load.
    @State private var briefing: String?
    @State private var error: String?
    @State private var path: [Game.ID] = []
    @Environment(\.popToRoot) private var popToRoot
    private var store: FantasyStore { .shared }

    private var pastWeek: Int? { chosenWeek ?? base?.latestWeek }
    private var games: [Game] { (past?.entries ?? []).map(\.game) + (base?.upcoming ?? []).map(\.game) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if store.active != nil {
                        GlassPicker(selection: $tab)
                    }
                    content
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .backdrop(.sportsNavy)
            .environment(\.colorScheme, .dark)
            .navigationTitle(store.active?.name ?? "Fantasy")
            // The league name is a dropdown of every saved league, grouped by app, in place of the plain title.
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        ForEach(FantasyProvider.allCases) { provider in
                            let leagues = store.leagues.filter { $0.provider == provider }
                            if !leagues.isEmpty {
                                Section(provider.title) {
                                    ForEach(leagues) { league in
                                        Toggle(league.name, isOn: Binding(get: { league.id == store.active?.id },
                                                                          set: { if $0 { store.activeID = league.id } }))
                                    }
                                }
                            }
                        }
                        // Only separates leagues from Manage Leagues…; with none added it would sit alone at the top.
                        if !store.leagues.isEmpty { Divider() }
                        SettingsLink { Text("Manage Leagues…") }
                    } label: {
                        HStack(spacing: 8) {
                            Text(store.active?.name ?? "Fantasy").font(.headline)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await loadBase()
                            if let week = pastWeek { await loadPast(week: week) }
                            await loadSeason()
                        }
                    }
                    .keyboardShortcut("r")
                }
            }
            .navigationDestination(for: Game.ID.self) { id in
                if let game = games.first(where: { $0.id == id }) {
                    GameDetailView(provider: provider, game: game)
                }
            }
        }
        // Clicking this page's sidebar row again leaves any open game.
        .onChange(of: popToRoot) {
            path = []
            tab = .lineup
        }
        .task(id: store.active?.id) {
            base = nil; past = nil; season = nil; chosenWeek = nil; error = nil
            await loadBase()
            await loadSeason()
        }
        // The shown week reloads on change, and keeps polling while any of its games is live.
        .task(id: "\(store.active?.id ?? "")/\(pastWeek ?? 0)") {
            guard let week = pastWeek else { return }
            repeat {
                await loadPast(week: week)
                guard past?.entries.contains(where: { $0.game.status == .live }) == true else { return }
            } while (try? await Task.sleep(for: .seconds(30))) != nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.active == nil {
            ContentUnavailableView {
                Label("Set Up Fantasy", systemImage: "football")
            } description: {
                Text("Add a Sleeper or ESPN Fantasy league in Settings › Fantasy.")
            } actions: {
                SettingsLink { Text("Open Settings") }.buttonStyle(.glass)
            }
        } else if let base {
            switch tab {
            case .lineup:
                lineup(base)
            case .past:
                weekPicker(latest: base.latestWeek)
                if let past, past.week == pastWeek {
                    entries(past.entries, empty: "None of your players played this week.")
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            case .upcoming:
                Text("Week \(base.upcomingWeek)").font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
                entries(base.upcoming, empty: "None of your players have games coming up.")
            case .season:
                if let season {
                    FantasySeasonView(trend: season.trend, standings: season.standings)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            case .news:
                FantasyNewsView(base: base)
            }
        } else {
            Group {
                if let error {
                    ContentUnavailableView("Couldn’t Load Fantasy", systemImage: "wifi.exclamationmark", description: Text(error))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    /// "Week 6" with a menu of every played week back to week 1.
    private func weekPicker(latest: Int) -> some View {
        Menu {
            ForEach((1...max(1, latest)).reversed(), id: \.self) { week in
                Button("Week \(week)") { chosenWeek = week == latest ? nil : week }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Week \(pastWeek ?? latest)").font(.title2.weight(.bold))
                Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineup(_ base: Base) -> some View {
        if let matchup = base.matchup {
            MatchupCard(matchup: matchup, week: base.upcomingWeek)
        }
        WeekOverviewCard(base: base, overview: $briefing)
        SportsCard {
            columnHeader("Starters", base: base)
            ForEach(Array(base.team.lineup.enumerated()), id: \.offset) { _, slot in
                HStack(spacing: 10) {
                    SlotTag(label: slot.label)
                    if let player = slot.player {
                        lineupRow(player, base: base)
                    } else {
                        Text("Empty").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.vertical, 6)
            }
        }
        if !base.team.bench.isEmpty {
            SportsCard {
                columnHeader("Bench", base: base)
                ForEach(base.team.bench, id: \.id) { player in
                    HStack(spacing: 10) {
                        SlotTag(label: "BN")
                        lineupRow(player, base: base)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func lineupRow(_ player: FantasyPlayer, base: Base) -> some View {
        FantasyPlayerRow(player: player, next: nextGame(for: player, in: base),
                         projected: base.projections[player.id], lastWeek: base.lastWeekPoints[player.id],
                         espnID: base.espnID(player), byeWeek: player.team.flatMap { base.byes[$0] },
                         onBye: player.team.flatMap { base.byes[$0] } == base.upcomingWeek, news: base.news[player.id]?.first)
    }

    /// "Starters ……… PROJ  WK 6", lining up with each row's two numbers.
    private func columnHeader(_ title: String, base: Base) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("PROJ").frame(width: FantasyPlayerRow.columnWidth, alignment: .trailing)
            Text("WK \(max(1, base.upcomingWeek - 1))").frame(width: FantasyPlayerRow.columnWidth, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func entries(_ entries: [Entry], empty: String) -> some View {
        if entries.isEmpty {
            ContentUnavailableView("No Games", systemImage: "calendar", description: Text(empty))
                .frame(maxWidth: .infinity, minHeight: 200)
        }
        ForEach(entries) { entry in
            SportsCard {
                GameCardRows(games: [entry.game], showsDate: true)
                Divider().padding(.vertical, 4)
                ForEach(entry.players) { line in
                    FantasyPlayerRow(line: line, game: entry.game).padding(.vertical, 6)
                }
            }
        }
    }

    /// The player's game still to come this week (or under way), for the lineup's "vs DAL · Sun 1:00 PM".
    private func nextGame(for player: FantasyPlayer, in base: Base) -> Game? {
        let live = base.latestWeek == past?.week ? (past?.entries ?? []).filter { $0.game.status == .live } : []
        return (base.upcoming + live).map(\.game).first {
            $0.away.team.abbreviation == player.team || $0.home.team.abbreviation == player.team
        }
    }

    private func loadBase() async {
        guard let league = store.active else { return }
        do {
            let state = try await Sleeper.state() // the NFL calendar, the same for every provider
            let credentials = league.provider == .espn ? store.credentials(leagueID: league.leagueID) : nil
            async let teamTask = FantasyData.team(for: league, season: state.season, espnCredentials: credentials,
                                                  playersCache: Self.playersCache)
            // The latest week is the current one once its games have kicked off, else the one before;
            // upcoming is the current week while it has games left to play, else the next.
            let current = Sleeper.week(of: .now, state: state)
            async let currentTask = nflGames(week: current, state: state)
            let (team, currentGames) = try await (teamTask, currentTask)
            let latest = currentGames.contains { $0.status != .scheduled } ? current : max(1, current - 1)
            let upcomingWeek = currentGames.contains { $0.status == .scheduled } ? current : current + 1
            let coming = (upcomingWeek == current ? currentGames : try await nflGames(week: upcomingWeek, state: state))
                .filter { $0.status == .scheduled && involves($0, team) }
                .sorted { $0.startDate < $1.startDate }
            // Extras for the lineup; any that fail just leave their numbers blank.
            async let projectionsTask = (try? await FantasyData.projections(for: league, week: upcomingWeek, season: state.season,
                                                                            espnCredentials: credentials)) ?? [:]
            async let lastTask = (try? await FantasyData.points(for: league, week: upcomingWeek - 1, season: state.season,
                                                                espnCredentials: credentials)) ?? [:]
            let (projections, lastWeekPoints) = await (projectionsTask, lastTask)
            async let matchupTask = try? await FantasyData.matchup(for: league, week: upcomingWeek, season: state.season,
                                                                   projections: projections, espnCredentials: credentials)
            async let calendarTask = try? await FantasyData.calendar(for: league, season: state.season, state: state,
                                                                     espnCredentials: credentials)
            async let byesTask = (try? await ESPNProvider.nflByes(season: state.season)) ?? [:]
            async let idsTask = ESPNNews.espnIDs(for: team.players)
            let (matchup, calendar, byes, espnIDs) = await (matchupTask, calendarTask, byesTask, idsTask)
            // Latest news for each player ESPN knows.
            let news = await withTaskGroup(of: (String, [PlayerNews]).self) { group in
                for player in team.players {
                    guard let id = player.espnID ?? espnIDs[player.id] else { continue }
                    group.addTask { (player.id, (try? await ESPNNews.news(espnID: id)) ?? []) }
                }
                var all: [String: [PlayerNews]] = [:]
                for await (id, items) in group { all[id] = items }
                return all
            }
            guard league.id == store.active?.id else { return }
            briefing = nil // a fresh load gets a fresh briefing
            base = Base(league: league, state: state, team: team, latestWeek: latest, upcomingWeek: upcomingWeek,
                        upcoming: coming.map { entry($0, team: team, detail: nil, points: [:]) },
                        matchup: matchup, projections: projections, lastWeekPoints: lastWeekPoints,
                        calendar: calendar, byes: byes, news: news, espnIDs: espnIDs)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    static let playersCache = URL.cachesDirectory.appending(path: "sleeper-players-v3.json")

    /// Every completed week (those before the upcoming one) and the standings.
    private func loadSeason() async {
        guard let base, base.league.id == store.active?.id else { return }
        let league = base.league
        let credentials = league.provider == .espn ? store.credentials(leagueID: league.leagueID) : nil
        let weeks = Array(1..<max(1, base.upcomingWeek))
        async let resultsTask = try? await FantasyData.season(for: league, weeks: weeks, season: base.state.season,
                                                              espnCredentials: credentials, playersCache: Self.playersCache)
        async let standingsTask = try? await FantasyData.standings(for: league, season: base.state.season, espnCredentials: credentials)
        let (results, standings) = await (resultsTask, standingsTask)
        guard league.id == store.active?.id else { return }
        season = Season(trend: SeasonTrend(weeks: results ?? []), standings: FantasyStanding.ranked(standings ?? []))
    }

    private func loadPast(week: Int) async {
        guard let base, base.league.id == store.active?.id else { return }
        do {
            let league = base.league, team = base.team, provider = provider
            let credentials = league.provider == .espn ? store.credentials(leagueID: league.leagueID) : nil
            let played = try await nflGames(week: week, state: base.state)
                .filter { $0.status != .scheduled && involves($0, team) }
                .sorted { ($0.status == .live ? 0 : 1, $1.startDate) < ($1.status == .live ? 0 : 1, $0.startDate) }
            async let pointsTask = (try? await FantasyData.points(for: league, week: week, season: base.state.season,
                                                                  espnCredentials: credentials)) ?? [:]
            async let detailsTask = withTaskGroup(of: (Game.ID, GameDetail?).self) { group in
                for game in played {
                    group.addTask { (game.id, try? await provider.gameDetail(for: game)) }
                }
                var all: [Game.ID: GameDetail] = [:]
                for await (id, detail) in group { all[id] = detail }
                return all
            }
            let (points, details) = await (pointsTask, detailsTask)
            guard league.id == store.active?.id, week == pastWeek else { return }
            past = (week, played.map { entry($0, team: team, detail: details[$0.id], points: points) })
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func involves(_ game: Game, _ team: FantasyTeam) -> Bool {
        team.players.contains { $0.team == game.away.team.abbreviation || $0.team == game.home.team.abbreviation }
    }

    private func entry(_ game: Game, team: FantasyTeam, detail: GameDetail?, points: [String: Double]) -> Entry {
        let sides = [game.away.team.abbreviation, game.home.team.abbreviation]
        let starters = team.starters
        let lines = team.players.filter { sides.contains($0.team ?? "") }.map { player in
            let espnID = Self.espnID(for: player, in: detail, game: game)
            return Line(player: player, isStarter: starters.contains(player.id), points: points[player.id],
                        stats: Self.stats(espnID: espnID, in: detail), espnID: espnID)
        }
        .sorted { ($0.isStarter ? 0 : 1, -($0.points ?? 0)) < ($1.isStarter ? 0 : 1, -($1.points ?? 0)) }
        return Entry(game: game, players: lines)
    }

    /// Every NFL game in one fantasy week.
    private func nflGames(week: Int, state: Sleeper.State) async throws -> [Game] {
        try await ESPNProvider.nflWeek(season: state.season, week: week)
    }

    /// Name matches only look at the player's own team, so two same-named players in one game can't swap.
    static func espnID(for player: FantasyPlayer, in detail: GameDetail?, game: Game) -> String? {
        if let id = player.espnID { return id }
        let team = [game.away.team, game.home.team].first { $0.abbreviation == player.team }
        return detail?.boxScores.lazy.filter { $0.teamID == team?.id }.flatMap(\.rows)
            .first { Sleeper.sameName($0.name, player.name) }?.id
    }

    /// "Passing: 22/37 C/ATT, 245 YDS, 2 TD" for each box score category the player appears in.
    static func stats(espnID: String?, in detail: GameDetail?) -> [String] {
        guard let espnID, let detail else { return [] }
        let skipped: Set<String> = ["AVG", "LONG", "QBR", "RTG", "YDS/G"]
        return detail.boxScores.compactMap { box in
            guard let row = box.rows.first(where: { $0.id == espnID }) else { return nil }
            let pairs = zip(box.labels, row.stats).filter { !skipped.contains($0.0) }.map { "\($0.1) \($0.0)" }
            return "\(box.category.capitalized): " + pairs.joined(separator: ", ")
        }
    }
}

private struct SlotTag: View {
    let label: String

    var body: some View {
        Text(label).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7).frame(width: 44)
            .padding(.vertical, 3).background(.white.opacity(0.12), in: .capsule)
    }
}

/// One of your players: headshot (or team logo for a defence), name, team and position, bench tag,
/// then stat lines and fantasy points once their game has started, in the style of the game leaders card.
private struct FantasyPlayerRow: View {
    let player: FantasyPlayer
    var isStarter = true
    var points: Double?
    var stats: [String] = []
    var espnID: String?
    /// The game shown with the player; nil on the lineup, where `next` gives their coming game instead.
    var game: Game?
    var next: Game?

    init(line: FantasyView.Line, game: Game) {
        player = line.player; isStarter = line.isStarter; points = line.points
        stats = line.stats; espnID = line.espnID; self.game = game
    }

    /// Lineup only: this week's projection and last week's points, as two right-hand columns.
    var projected: Double?
    var lastWeek: Double?
    private var isLineup = false
    static let columnWidth: CGFloat = 56

    /// Lineup only: bye week, whether it's this week, and the latest news line.
    var byeWeek: Int?
    var onBye = false
    var news: PlayerNews?

    init(player: FantasyPlayer, next: Game?, projected: Double?, lastWeek: Double?,
         espnID: String?, byeWeek: Int?, onBye: Bool, news: PlayerNews?) {
        self.player = player; self.espnID = espnID; self.next = next
        self.projected = projected; self.lastWeek = lastWeek; isLineup = true
        self.byeWeek = byeWeek; self.onBye = onBye; self.news = news
    }

    private var hasStarted: Bool { game.map { $0.status != .scheduled } ?? false }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                // Defences show their team's logo rather than a photo.
                if player.position != "DEF", let url = espnID.flatMap(Sleeper.headshotURL) ?? player.photoURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                        Image(systemName: "person.fill").font(.title3).foregroundStyle(.secondary)
                    }
                } else if let team = (game ?? next).flatMap({ g in [g.away.team, g.home.team].first { $0.abbreviation == player.team } }) {
                    TeamLogo(team: team, size: 30)
                } else {
                    Image(systemName: player.position == "DEF" ? "shield.fill" : "person.fill").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.12))
            .clipShape(.circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.25)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name).font(.headline).lineLimit(1)
                    let tag = [player.team, player.position].compactMap { $0 }.joined(separator: " - ")
                    if !tag.isEmpty {
                        Text(tag).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !isStarter {
                        Text("BN").font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.white.opacity(0.15), in: .capsule)
                    }
                }
                if isLineup {
                    HStack(spacing: 6) {
                        StatusTag(injury: player.injury, onBye: onBye)
                        Text(next.map(matchup) ?? (onBye ? "On bye this week" : "No game to come this week"))
                        if let byeWeek, !onBye { Text("· Bye Wk \(byeWeek)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if let news {
                        Text(news.headline).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                            .help(news.story ?? news.headline)
                    }
                } else if let next {
                    Text(matchup(next)).font(.caption).foregroundStyle(.secondary)
                } else if game == nil {
                    Text("No game to come this week").font(.caption).foregroundStyle(.secondary)
                } else if !hasStarted {
                    EmptyView()
                } else if stats.isEmpty && player.position != "DEF" {
                    Text(game?.status == .live ? "No stats yet" : "No stats").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(stats, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isLineup {
                ForEach([projected, lastWeek].indices, id: \.self) { index in
                    let value = index == 0 ? projected : lastWeek
                    Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                        .font(.score(20)).monospacedDigit()
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .frame(width: Self.columnWidth, alignment: .trailing)
                }
            } else if hasStarted {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(points.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                        .font(.score(28)).monospacedDigit()
                    Text("PTS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(isStarter ? 1 : 0.7)
        .accessibilityElement(children: .combine)
    }

    /// "vs DAL · Sun 1:00 PM" or "@ KC · Live".
    private func matchup(_ game: Game) -> String {
        let home = game.home.team.abbreviation == player.team
        let opponent = home ? game.away.team.abbreviation : game.home.team.abbreviation
        let when = game.status == .live ? "Live" : game.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(home ? "vs" : "@") \(opponent) · \(when)"
    }
}

/// This week's head-to-head, Sleeper-style in our cards: each manager's team, projected total in big type
/// with points so far beneath, and a bar splitting the two projections.
private struct MatchupCard: View {
    let matchup: FantasyMatchup
    let week: Int

    var body: some View {
        SportsCard(title: "Week \(week) Matchup") {
            HStack(alignment: .center, spacing: 12) {
                side(matchup.me, leading: true)
                Text("VS").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36).background(.white.opacity(0.1), in: .circle)
                if let opponent = matchup.opponent {
                    side(opponent, leading: false)
                } else {
                    Text("Bye week").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            // Win chances: the bar splits at yours, the favourite's side in green, with each side's percentage beneath.
            if let chance = matchup.winProbability {
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        HStack(spacing: 3) {
                            Capsule().fill(chance >= 0.5 ? Color.green : Color.pink)
                                .frame(width: max(4, (geometry.size.width - 3) * chance))
                            Capsule().fill(chance < 0.5 ? Color.green : Color.pink)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        Text(percent(chance))
                        Spacer()
                        Text("Win chance").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(percent(1 - chance))
                    }
                    .font(.caption.weight(.bold)).monospacedDigit()
                }
                .padding(.bottom, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Win chance \(percent(chance)) to \(percent(1 - chance))")
            }
        }
    }

    private func side(_ side: FantasyMatchup.Side, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 10) {
            HStack(spacing: 10) {
                if leading { avatar(side) }
                VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
                    if let manager = side.manager {
                        Text("@\(manager)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(side.teamName).font(.headline).lineLimit(1)
                }
                if !leading { avatar(side) }
            }
            // Big: points scored this week ("–" before kickoff). Beneath: the projected total.
            VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
                Text(side.points > 0 ? side.points.formatted(.number.precision(.fractionLength(2))) : "–")
                    .font(.score(34)).monospacedDigit()
                HStack(spacing: 4) {
                    Text("PROJ").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(side.projected.formatted(.number.precision(.fractionLength(2)))).font(.caption.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func avatar(_ side: FantasyMatchup.Side) -> some View {
        AsyncImage(url: side.avatarURL) { $0.resizable().scaledToFill() } placeholder: {
            Image(systemName: "person.fill").foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
        .background(.white.opacity(0.12))
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
    }
}

/// Healthy / Questionable / Out / IR / Bye, coloured like an injury report.
struct StatusTag: View {
    let injury: FantasyPlayer.Injury?
    var onBye = false

    var body: some View {
        let (text, color) = label
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule)
            .help(injury.map { [$0.status, $0.detail].compactMap { $0 }.joined(separator: " · ") } ?? text)
    }

    private var label: (String, Color) {
        if onBye { return ("Bye", .gray) }
        switch injury?.severity ?? 0 {
        case 0: return ("Healthy", .green)
        case 1: return ("Q", .yellow)
        case 2: return ("D", .orange)
        default: return (injury?.status ?? "Out", .red)
        }
    }
}
