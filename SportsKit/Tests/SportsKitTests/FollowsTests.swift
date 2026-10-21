import Foundation
import SwiftData
import Testing
@testable import SportsKit

private func team(_ id: String) -> Team {
    Team(id: id, abbreviation: "T\(id)", displayName: "Team \(id)", shortName: "\(id)s",
         colorHex: "aa0000", alternateColorHex: nil, logoURL: URL(string: "https://example.com/\(id).png"))
}

private func game(league: League.ID, home: String, away: String) -> Game {
    Game(id: "\(home)-\(away)", leagueID: league, startDate: .now, status: .scheduled, period: 0, clock: "",
         statusDetail: "", home: .init(team: team(home), score: nil, periodScores: []),
         away: .init(team: team(away), score: nil, periodScores: []))
}

@Suite struct FollowsTests {
    @Test func followedTeamIncludesItsGamesOnly() {
        let follows = Follows(leagueIDs: [], teams: [.init(leagueID: "nfl", teamID: "12")])
        #expect(follows.includes(game(league: "nfl", home: "12", away: "4")))
        #expect(follows.includes(game(league: "nfl", home: "4", away: "12")))
        #expect(!follows.includes(game(league: "nfl", home: "4", away: "5")))
        // Team IDs are only unique within a league.
        #expect(!follows.includes(game(league: "nba", home: "12", away: "4")))
    }

    @Test func followedLeagueIncludesEveryGame() {
        let follows = Follows(leagueIDs: ["nfl"], teams: [])
        #expect(follows.includes(game(league: "nfl", home: "4", away: "5")))
        #expect(!follows.includes(game(league: "nba", home: "4", away: "5")))
    }

    @Test func pollsFollowedLeaguesAndTeamLeagues() {
        let follows = Follows(leagueIDs: ["nfl"], teams: [.init(leagueID: "nba", teamID: "1")])
        #expect(follows.leagueIDsToPoll == ["nfl", "nba"])
        #expect(Follows(leagueIDs: [], teams: []).isEmpty)
    }
}

@Suite @MainActor struct FollowPersistenceTests {
    private let storeURL = FileManager.default.temporaryDirectory
        .appending(path: "follows-\(UUID().uuidString).store")

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Schema(sportsModels),
                                           configurations: ModelConfiguration(url: storeURL))
        return ModelContext(container)
    }

    @Test func followsSurviveRelaunch() throws {
        do {
            let context = try makeContext()
            context.insert(FollowedLeague(leagueID: "nfl"))
            context.insert(FollowedTeam(team: team("12"), leagueID: "nfl"))
            try context.save()
        }
        // A fresh container on the same file stands in for a relaunch.
        let context = try makeContext()
        let teams = try context.fetch(FetchDescriptor<FollowedTeam>())
        let leagues = try context.fetch(FetchDescriptor<FollowedLeague>())
        #expect(leagues.map(\.leagueID) == ["nfl"])
        #expect(teams.count == 1)
        #expect(teams.first?.team == team("12").withoutAlternateColor)
    }

    @Test func followingTwiceKeepsOneRecord() throws {
        let context = try makeContext()
        context.insert(FollowedTeam(team: team("12"), leagueID: "nfl"))
        try context.save()
        context.insert(FollowedTeam(team: team("12"), leagueID: "nfl"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<FollowedTeam>()) == 1)
    }
}

private extension Team {
    var withoutAlternateColor: Team {
        Team(id: id, abbreviation: abbreviation, displayName: displayName, shortName: shortName,
             colorHex: colorHex, alternateColorHex: nil, logoURL: logoURL)
    }
}
