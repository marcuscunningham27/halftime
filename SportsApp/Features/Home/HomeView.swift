import SportsKit
import SwiftData
import SwiftUI

/// Mirrors the iOS Sports home screen: Yesterday / Today / Upcoming, My Teams first, then each league.
struct HomeView: View {
    enum Day: String, CaseIterable, Identifiable {
        case yesterday = "Yesterday", today = "Today", upcoming = "Upcoming"
        var id: Self { self }

        /// nil follows today (and rolls over at midnight).
        var date: Date? {
            switch self {
            case .yesterday: Calendar.current.date(byAdding: .day, value: -1, to: .now)
            case .today: nil
            case .upcoming: Calendar.current.date(byAdding: .day, value: 1, to: .now)
            }
        }
    }

    let provider: any SportsProvider
    let leagues: [League]
    let showLeague: (League) -> Void

    @State private var day = Day.today
    @State private var poller: ScoreboardPoller?
    @State private var path: [Game.ID] = []
    @Environment(\.popToRoot) private var popToRoot
    @Query private var followedTeams: [FollowedTeam]

    private var refs: Set<Follows.TeamRef> {
        Set(followedTeams.map { Follows.TeamRef(leagueID: $0.leagueID, teamID: $0.teamID) })
    }

    private var myTeamGames: [Game] {
        let refs = refs
        return ordered((poller?.games ?? []).filter { game in
            refs.contains(.init(leagueID: game.leagueID, teamID: game.home.team.id))
                || refs.contains(.init(leagueID: game.leagueID, teamID: game.away.team.id))
        })
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    GlassPicker(selection: $day)
                        .padding(.bottom, 14)

                    SportsCard {
                        content
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .backdrop(.sportsGreen)
            .environment(\.colorScheme, .dark)
            .navigationTitle("Home")
            // The app's wordmark in place of the plain title, as iOS Sports shows its own.
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 8) {
                        HalftimeMark(size: 32)
                        Text("Halftime").font(.system(size: 30, weight: .bold))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Halftime")
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.flexible)
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await poller?.refresh() } }
                        .keyboardShortcut("r")
                }
            }
            .navigationDestination(for: Game.ID.self) { id in
                if let game = poller?.games.first(where: { $0.id == id }) {
                    GameDetailView(provider: provider, game: game)
                }
            }
        }
        // Clicking this page's sidebar row again leaves any open game.
        .onChange(of: popToRoot) { path = [] }
        .task(id: day) {
            path = []
            let poller = ScoreboardPoller(provider: provider, leagues: leagues, date: day.date)
            self.poller = poller
            await poller.run()
        }
    }

    @ViewBuilder
    private var content: some View {
        let games = poller?.games ?? []
        if games.isEmpty {
            Group {
                if poller?.isLoading ?? true {
                    ProgressView()
                } else {
                    ContentUnavailableView("No Games \(day == .today ? "Today" : day.rawValue)", systemImage: "calendar")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            let mine = myTeamGames
            if !mine.isEmpty {
                SectionHeader(title: "My Teams") { Image(systemName: "star.fill") }
                GameCardRows(games: mine, followed: refs)
            }
            // Games already under My Teams aren't repeated in their league.
            let mineIDs = Set(mine.map(\.id))
            ForEach(leagues) { league in
                let leagueGames = ordered(games.filter { $0.leagueID == league.id && !mineIDs.contains($0.id) })
                if !leagueGames.isEmpty {
                    if league != leagues.first || !mine.isEmpty { Divider().padding(.top, 6) }
                    SectionHeader(title: league.abbreviation, action: { showLeague(league) }) {
                        LeagueLogo(league: league)
                    }
                    GameCardRows(games: leagueGames, followed: refs)
                }
            }
        }
    }

    /// Live first, then upcoming, then finished.
    private func ordered(_ games: [Game]) -> [Game] {
        let order: [Game.Status] = [.live, .scheduled, .final]
        return games.sorted { order.firstIndex(of: $0.status)! < order.firstIndex(of: $1.status)! }
    }
}

/// The app icon's markings (halfway line, centre circle and spot) on a clear glass tile, without its colours.
struct HalftimeMark: View {
    var size: CGFloat = 24

    var body: some View {
        let line = size * 0.055
        ZStack {
            Rectangle().frame(width: line)
            Circle().stroke(lineWidth: line).frame(width: size * 0.44, height: size * 0.44)
            Circle().frame(width: size * 0.1, height: size * 0.1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24))
        .glassEffect(.clear, in: .rect(cornerRadius: size * 0.24))
    }
}
