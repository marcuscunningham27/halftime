import SportsKit
import SwiftData
import SwiftUI

/// A league (optionally one team) for a chosen day, in iOS-style cards: live, upcoming, then results.
/// On today's date it also shows the most recent results grouped by day, then the standings.
/// Yesterday / Today / Upcoming switch quickly, as on Home; Upcoming lists the games ahead, grouped by day.
struct ScoreboardView: View {
    let provider: any SportsProvider
    let league: League
    var team: Team?

    @State private var date = Date.now
    @State private var poller: ScoreboardPoller?
    @State private var path: [Game.ID] = []
    @Environment(\.popToRoot) private var popToRoot
    @State private var recent: [Game] = []
    /// Showing the games ahead rather than one day.
    @State private var showsUpcoming = false
    @State private var upcomingGames: [Game]?
    @State private var upcomingReload = 0
    @Query private var followedTeams: [FollowedTeam]

    private var showsRecent: Bool { Calendar.current.isDateInToday(date) }
    private var followed: Set<Follows.TeamRef> {
        Set(followedTeams.map { Follows.TeamRef(leagueID: $0.leagueID, teamID: $0.teamID) })
    }

    private func involvesTeam(_ game: Game) -> Bool {
        team == nil || game.home.team.id == team?.id || game.away.team.id == team?.id
    }

    private var games: [Game] {
        (poller?.games ?? []).filter(involvesTeam)
    }

    /// Today's finals plus recent ones, newest first; a game that just finished appears once.
    private var finals: [Game] {
        let today = games.filter { $0.status == .final }
        let ids = Set(today.map(\.id))
        return (today + recent.filter { !ids.contains($0.id) && involvesTeam($0) }).sorted { $0.startDate > $1.startDate }
    }

    /// The picker's value: Upcoming, or Yesterday/Today when that's the date shown (none for other dates).
    private var day: Binding<HomeView.Day?> {
        Binding {
            if showsUpcoming { return .upcoming }
            if Calendar.current.isDateInToday(date) { return .today }
            if Calendar.current.isDateInYesterday(date) { return .yesterday }
            return nil
        } set: { day in
            showsUpcoming = day == .upcoming
            date = day == .yesterday ? Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now : .now
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    GlassPicker(selection: day, options: HomeView.Day.allCases.map { (Optional($0), $0.rawValue) })
                    if showsUpcoming {
                        upcomingContent
                    } else {
                        dayContent
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .backdrop(.sportsNavy)
            .environment(\.colorScheme, .dark)
            .navigationTitle(team?.displayName ?? league.abbreviation)
            .navigationSubtitle(showsUpcoming ? "Coming up" : date.formatted(date: .complete, time: .omitted))
            .toolbar { toolbar }
            .navigationDestination(for: Game.ID.self) { id in
                if let game = games.first(where: { $0.id == id }) ?? recent.first(where: { $0.id == id })
                    ?? upcomingGames?.first(where: { $0.id == id }) {
                    GameDetailView(provider: provider, game: game)
                }
            }
        }
        // Clicking this page's sidebar row again leaves any open game.
        .onChange(of: popToRoot) { path = [] }
        // The next week of league games, or the next three weeks of a team's (weekly sports play less often).
        .task(id: "\(showsUpcoming)/\(upcomingReload)") {
            guard showsUpcoming, upcomingGames == nil else { return }
            let provider = provider, league = league
            let days = (1...(team == nil ? 7 : 21)).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
            let found = await withTaskGroup(of: [Game].self) { group in
                for day in days { group.addTask { (try? await provider.scoreboard(league: league, date: day)) ?? [] } }
                var all: [Game.ID: Game] = [:]
                for await games in group { for game in games { all[game.id] = game } }
                return Array(all.values)
            }
            upcomingGames = found.filter { $0.status == .scheduled && involvesTeam($0) }.sorted { $0.startDate < $1.startDate }
        }
        .task(id: date) {
            path = []
            // shortcut: duplicates the menu bar's requests while showing today; share one poller if ESPN rate-limits.
            let poller = ScoreboardPoller(provider: provider, leagues: [league], date: date)
            self.poller = poller
            await poller.run()
        }
        // Finals don't change, so recent results load once per visit rather than polling.
        .task(id: date) {
            recent = []
            guard showsRecent else { return }
            recent = (try? await provider.recentResults(league: league, before: date)) ?? []
        }
    }

    @ViewBuilder
    private var upcomingContent: some View {
        if let upcomingGames {
            let days = Dictionary(grouping: upcomingGames) { Calendar.current.startOfDay(for: $0.startDate) }
            ForEach(days.keys.sorted(), id: \.self) { day in
                section(day.formatted(.dateTime.weekday(.wide).day().month(.wide)), days[day] ?? [])
            }
            if upcomingGames.isEmpty {
                ContentUnavailableView("Nothing Coming Up", systemImage: league.symbolName,
                                       description: Text("No \(team?.shortName ?? league.abbreviation) games in the next \(team == nil ? "week" : "three weeks")."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    @ViewBuilder
    private var dayContent: some View {
                    section("Live", games.filter { $0.status == .live })
                    section("Upcoming", games.filter { $0.status == .scheduled })
                    if showsRecent {
                        // Nothing on today: say so first, then the latest results under their own heading.
                        if games.isEmpty, !finals.isEmpty, poller?.isLoading == false {
                            ContentUnavailableView("No Games", systemImage: league.symbolName,
                                                   description: Text("There are no \(team?.shortName ?? league.abbreviation) games on this day."))
                            Text("Recent Results").font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        let days = Dictionary(grouping: finals) { Calendar.current.startOfDay(for: $0.startDate) }
                        ForEach(days.keys.sorted(by: >), id: \.self) { day in
                            section(Calendar.current.isDateInToday(day) ? "Final" : day.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                                    days[day] ?? [])
                        }
                    } else {
                        section("Final", games.filter { $0.status == .final })
                    }
                    if games.isEmpty && (!showsRecent || finals.isEmpty) {
                        emptyState.frame(maxWidth: .infinity, minHeight: 220)
                    }
                    if team == nil, showsRecent {
                        StandingsView(provider: provider, league: league, followed: followed)
                    }
    }

    @ViewBuilder
    private var emptyState: some View {
        if poller?.isLoading ?? true {
            ProgressView()
        } else if let error = poller?.error {
            ContentUnavailableView {
                Label("Couldn’t Load Scores", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await poller?.refresh() } }
                    .buttonStyle(.glass)
            }
        } else {
            ContentUnavailableView("No Games", systemImage: league.symbolName,
                                   description: Text("There are no \(team?.shortName ?? league.abbreviation) games on this day."))
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ matching: [Game]) -> some View {
        if !matching.isEmpty {
            SportsCard(title: title) {
                GameCardRows(games: matching, followed: followed)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        dateAndFollowControls
        ToolbarItem {
            Button("Refresh", systemImage: "arrow.clockwise") {
                if showsUpcoming { upcomingGames = nil; upcomingReload += 1 }
                Task { await poller?.refresh() }
            }
                .keyboardShortcut("r")
                .disabled(poller?.isLoading ?? true)
        }
    }

    @ToolbarContentBuilder
    private var dateAndFollowControls: some ToolbarContent {
        ToolbarItemGroup {
            ControlGroup {
                Button("Previous Day", systemImage: "chevron.left") { shiftDay(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Today") { date = .now; showsUpcoming = false }
                    .keyboardShortcut("t")
                    .disabled(Calendar.current.isDateInToday(date) && !showsUpcoming)
                Button("Next Day", systemImage: "chevron.right") { shiftDay(1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            DatePicker("Date", selection: Binding(get: { date }, set: { date = $0; showsUpcoming = false }), displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .padding(.horizontal, 10) // keeps the date text off the glass capsule's edge
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            if let team {
                FollowTeamButton(team: team, leagueID: league.id)
            } else {
                FollowLeagueButton(league: league)
            }
        }
    }

    private func shiftDay(_ days: Int) {
        showsUpcoming = false
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
