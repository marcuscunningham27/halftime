import SportsKit
import SwiftData
import SwiftUI

/// Star toggle for a team. Following asks for notification permission the first time.
struct FollowTeamButton: View {
    let team: Team
    let leagueID: League.ID

    @Environment(\.modelContext) private var context
    @Query private var matches: [FollowedTeam]

    init(team: Team, leagueID: League.ID) {
        self.team = team
        self.leagueID = leagueID
        let teamID = team.id
        _matches = Query(filter: #Predicate { $0.teamID == teamID && $0.leagueID == leagueID })
    }

    var body: some View {
        let isFollowing = !matches.isEmpty
        Button(isFollowing ? "Unfollow \(team.shortName)" : "Follow \(team.shortName)",
               systemImage: isFollowing ? "star.fill" : "star") {
            if isFollowing {
                try? context.unfollow(Follows.TeamRef(leagueID: leagueID, teamID: team.id))
            } else {
                try? context.follow(team, leagueID: leagueID)
                NotificationService.requestAuthorization()
            }
        }
    }
}

/// Star toggle for a league.
struct FollowLeagueButton: View {
    let league: League

    @Environment(\.modelContext) private var context
    @Query private var matches: [FollowedLeague]

    init(league: League) {
        self.league = league
        let leagueID = league.id
        _matches = Query(filter: #Predicate { $0.leagueID == leagueID })
    }

    var body: some View {
        let isFollowing = !matches.isEmpty
        Button(isFollowing ? "Unfollow \(league.abbreviation)" : "Follow \(league.abbreviation)",
               systemImage: isFollowing ? "star.fill" : "star") {
            if isFollowing {
                try? context.unfollow(leagueID: league.id)
            } else {
                try? context.follow(leagueID: league.id)
                NotificationService.requestAuthorization()
            }
        }
    }
}
