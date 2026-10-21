import SportsKit
import SwiftData
import SwiftUI
import WidgetKit

/// The menu bar item: the pinned live game's score, or a sports icon when nothing followed is live.
/// Also drives polling, so only followed leagues are fetched, and mirrors follows to the widget,
/// since this is the one view alive for as long as the app runs.
struct MenuBarLabel: View {
    let scores: ScoreboardPoller

    @Query private var followedLeagues: [FollowedLeague]
    @Query(sort: \FollowedTeam.createdAt) private var followedTeams: [FollowedTeam]

    var body: some View {
        let follows = Follows(leagues: followedLeagues, teams: followedTeams)
        Group {
            // Pinned game = earliest live followed game.
            if let game = scores.games.first(where: { $0.status == .live && follows.includes($0) }) {
                Text(game.compactScore)
                    .monospacedDigit()
            } else {
                Image(systemName: "sportscourt")
                    .accessibilityLabel("Sports")
            }
        }
        // Restarts, and refetches at once, whenever the set of followed leagues changes.
        .task(id: follows.leagueIDsToPoll) {
            scores.leagues = League.all.filter { follows.leagueIDsToPoll.contains($0.id) }
            await scores.run()
        }
        // Launched without its window (restored closed, or at login) in Close to Menu mode: no Dock icon.
        .onAppear {
            if !NSApp.windows.contains(where: { $0.identifier?.rawValue == "main" && $0.isVisible }) {
                MenuBarMode.windowClosed()
            }
        }
        .onChange(of: followedTeams.map(\.teamID) + followedLeagues.map(\.leagueID), initial: true) {
            WidgetTeam.save(followedTeams.map { WidgetTeam(leagueID: $0.leagueID, teamID: $0.teamID, name: $0.displayName) })
            WidgetTeam.saveLeagues(followedLeagues.map(\.leagueID))
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
