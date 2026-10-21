import Foundation
import Testing
@testable import SportsKit

/// Shaped like ESPN's league response with view=mTeam, mRoster and mSettings.
private let league = #"""
{"id": 123,
 "settings": {"name": "Office League", "rosterSettings": {"lineupSlotCounts": {"0": 1, "2": 2, "23": 1, "16": 1, "20": 6}}},
 "members": [{"id": "{OWNER-4}", "displayName": "marcus"}],
 "schedule": [{"matchupPeriodId": 6, "home": {"teamId": 4, "totalPoints": 21.5}, "away": {"teamId": 1, "totalPoints": 0}}],
 "teams": [
  {"id": 1, "location": "Team", "nickname": "Taco", "roster": {"entries": []}},
  {"id": 4, "name": "Marcus's Team", "owners": ["{OWNER-4}"], "logo": "https://example.com/logo.png", "roster": {"entries": [
    {"lineupSlotId": 0, "playerPoolEntry": {"player": {"id": 3139477, "fullName": "Patrick Mahomes", "defaultPositionId": 1, "proTeamId": 12,
      "stats": [{"scoringPeriodId": 6, "statSourceId": 0, "appliedTotal": 21.5}, {"scoringPeriodId": 6, "statSourceId": 1, "appliedTotal": 19.0}]}}},
    {"lineupSlotId": 2, "playerPoolEntry": {"player": {"id": 4241457, "fullName": "Najee Harris", "defaultPositionId": 2, "proTeamId": 0}}},
    {"lineupSlotId": 16, "playerPoolEntry": {"player": {"id": -16028, "fullName": "Commanders D/ST", "defaultPositionId": 16, "proTeamId": 28}}},
    {"lineupSlotId": 20, "playerPoolEntry": {"player": {"id": 4430807, "fullName": "Malik Nabers", "defaultPositionId": 3, "proTeamId": 19}}}
  ]}}
 ]}
"""#

@Suite struct ESPNFantasyTests {
    @Test func readsLeagueNameAndTeams() throws {
        let info = try ESPNFantasy.parseLeague(Data(league.utf8))
        #expect(info.name == "Office League")
        #expect(info.teams.map(\.name) == ["Team Taco", "Marcus's Team"])
        #expect(info.teams.map(\.id) == ["1", "4"])
    }

    @Test func buildsLineupInSlotOrderWithEmptySlots() throws {
        let team = try #require(try ESPNFantasy.parseTeam(Data(league.utf8), teamID: "4"))
        #expect(team.lineup.map(\.label) == ["QB", "RB", "RB", "FLEX", "DEF"])
        #expect(team.lineup.map { $0.player?.name } == ["Patrick Mahomes", "Najee Harris", nil, nil, "Commanders D/ST"])
        #expect(team.bench.map(\.name) == ["Malik Nabers"])
        let mahomes = try #require(team.lineup.first?.player)
        #expect(mahomes.team == "KC" && mahomes.position == "QB" && mahomes.espnID == "3139477")
        let defence = try #require(team.lineup.last?.player)
        #expect(defence.espnID == nil && defence.team == "WSH" && defence.position == "DEF")
        #expect(try ESPNFantasy.parseTeam(Data(league.utf8), teamID: "99") == nil)
    }

    @Test func pointsAreActualsNotProjections() throws {
        #expect(try ESPNFantasy.parsePoints(Data(league.utf8), week: 6) == ["3139477": 21.5])
        #expect(try ESPNFantasy.parsePoints(Data(league.utf8), week: 5).isEmpty)
    }

    @Test func projectionsAndMatchup() throws {
        let projections = try ESPNFantasy.parsePoints(Data(league.utf8), week: 6, source: 1)
        #expect(projections == ["3139477": 19.0])
        let matchup = try #require(try ESPNFantasy.parseMatchup(Data(league.utf8), teamID: "4", week: 6, projections: projections))
        #expect(matchup.me.teamName == "Marcus's Team" && matchup.me.manager == "marcus" && matchup.me.points == 21.5)
        #expect(matchup.me.projected == 19.0) // bench (Nabers) not counted
        #expect(matchup.opponent?.teamName == "Team Taco")
        #expect(try ESPNFantasy.parseMatchup(Data(league.utf8), teamID: "4", week: 7, projections: [:]) == nil)
    }
}
