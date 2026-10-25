import Foundation
import Testing
@testable import SportsKit

@Suite struct GameClockTests {
    private func game(_ league: League, period: Int) -> Game {
        let team = Team(id: "1", abbreviation: "T", displayName: "T", shortName: "T", colorHex: nil, alternateColorHex: nil, logoURL: nil)
        return Game(id: "1", leagueID: league.id, startDate: .now, status: .live, period: period, clock: "0:00", statusDetail: "",
                    home: .init(team: team, score: 31, periodScores: []), away: .init(team: team, score: 31, periodScores: []))
    }

    @Test func collegeOvertimeIsUntimed() {
        // College overtime is possessions from the 25 with no clock; ESPN leaves it at 0:00 and labels it "2OT".
        #expect(!game(.cfb, period: 6).showsGameClock)
        #expect(game(.cfb, period: 4).showsGameClock)
    }

    @Test func collegeOvertimePlaysHaveNoClock() throws {
        // Miami–Pitt ended in regulation, so its plays all keep their clock; stamp one into overtime to check.
        let url = try #require(Bundle.module.url(forResource: "cfb-summary", withExtension: "json", subdirectory: "Fixtures"))
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: #""period":{"number":4}"#, with: #""period":{"number":5}"#)
        let plays = try ESPNProvider.parseSummary(Data(json.utf8), leagueID: League.cfb.id).plays
        let overtime = plays.filter { $0.period == 5 }
        #expect(!overtime.isEmpty)
        #expect(overtime.allSatisfy { $0.clock.isEmpty })
        #expect(plays.filter { $0.period == 1 }.allSatisfy { !$0.clock.isEmpty })
    }

    @Test func nflOvertimeKeepsItsClock() {
        #expect(game(.nfl, period: 5).showsGameClock)
        #expect(game(.nba, period: 5).showsGameClock)
    }
}
