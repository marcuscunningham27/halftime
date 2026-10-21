import Foundation
import Testing
@testable import SportsKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func games(_ name: String) throws -> [Game] {
    try ESPNProvider.parseScoreboard(fixture(name), leagueID: League.nfl.id)
}

@Suite struct ESPNScoreboardTests {
    @Test func decodesEveryGameInTheWeek() throws {
        let games = try games("nfl-scoreboard-live")
        #expect(games.count == 14)
        #expect(games.allSatisfy { $0.leagueID == "nfl" })
    }

    @Test func decodesLiveGame() throws {
        let game = try #require(try games("nfl-scoreboard-live").first { $0.id == "401873008" })
        #expect(game.status == .live)
        #expect(game.period == 2)
        #expect(game.clock == "6:26")
        #expect(game.statusDetail == "6:26 - 2nd")
        #expect(game.startDate == Date(timeIntervalSince1970: 1_792_455_300)) // 2026-10-20T00:15Z
        #expect(game.home.team.abbreviation == "SF")
        #expect(game.home.team.displayName == "San Francisco 49ers")
        #expect(game.home.team.shortName == "49ers")
        #expect(game.home.team.colorHex == "aa0000")
        #expect(game.home.team.logoURL?.absoluteString == "https://a.espncdn.com/i/teamlogos/nfl/500/scoreboard/sf.png")
        #expect(game.home.score == 13)
        #expect(game.home.periodScores == [13, 0])
        #expect(game.away.team.abbreviation == "WSH")
        #expect(game.away.score == 3)
        #expect(game.home.record == "5-0")
    }

    @Test func decodesOvertimeFinal() throws {
        let game = try #require(try games("nfl-scoreboard-live").first { $0.id == "401872995" })
        #expect(game.status == .final)
        #expect(game.period == 5)
        #expect(game.statusDetail == "Final/OT")
        #expect(game.home.team.abbreviation == "DEN")
        #expect(game.home.score == 17)
        #expect(game.away.score == 14)
    }

    @Test func scheduledGameHasNoScores() throws {
        let game = try #require(try games("nfl-scoreboard-scheduled").first)
        #expect(game.status == .scheduled)
        #expect(game.away.team.abbreviation == "NE")
        #expect(game.home.team.abbreviation == "CHI")
        #expect(game.home.score == nil)
        #expect(game.away.score == nil)
        #expect(game.startDate == Date(timeIntervalSince1970: 1_792_714_500)) // 2026-10-23T00:15Z
    }

    @Test func scoreboardURL() {
        let url = ESPNEndpoints.scoreboard(path: "football/nfl", espnDay: "20261018")
        #expect(url.absoluteString == "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=20261018")
    }

    @Test func brisbaneDayStraddlesTwoEasternDays() throws {
        // Tue 20 Oct in Brisbane (UTC+10) runs from Mon 10:00 to Tue 10:00 in New York.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Australia/Brisbane"))
        let day = try #require(calendar.dateInterval(of: .day, for: Date(timeIntervalSince1970: 1_792_459_200)))
        #expect(ESPNEndpoints.espnDays(covering: day) == ["20261019", "20261020"])
    }

    @Test func newYorkDayIsOneEasternDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let day = try #require(calendar.dateInterval(of: .day, for: Date(timeIntervalSince1970: 1_792_459_200)))
        #expect(ESPNEndpoints.espnDays(covering: day) == ["20261019"])
    }

    @Test func rejectsUnsupportedLeague() async {
        await #expect(throws: ESPNError.self) {
            try await ESPNProvider().scoreboard(league: League(id: "xfl", name: "XFL", abbreviation: "XFL"), date: .now)
        }
    }
}

@Test func scoreboardReadsWhereToWatch() throws {
    let json = #"""
    {"events":[{"id":"1","date":"2026-10-22T23:00Z","competitions":[{
      "status":{"period":0,"displayClock":"0:00","type":{"state":"pre","completed":false,"shortDetail":"7:00 PM"}},
      "competitors":[{"homeAway":"home","team":{"id":"1","abbreviation":"PHI","displayName":"76ers","shortDisplayName":"76ers"}},
                     {"homeAway":"away","team":{"id":"2","abbreviation":"CLE","displayName":"Cavaliers","shortDisplayName":"Cavaliers"}}],
      "broadcasts":[{"market":"national","names":["ESPN"]}],
      "geoBroadcasts":[{"media":{"shortName":"NBC Sports Philadelphia"},"market":{"type":"Home"}},
                       {"media":{"shortName":"ESPN"},"market":{"type":"National"}},
                       {"media":{"shortName":"ESPN"},"market":{"type":"National"}}]}]}]}
    """#
    let games = try ESPNProvider.parseScoreboard(Data(json.utf8), leagueID: League.nba.id)
    #expect(games.first?.broadcasts == ["ESPN", "NBC Sports Philadelphia"])
}
