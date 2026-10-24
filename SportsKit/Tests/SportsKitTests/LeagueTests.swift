import Foundation
import Testing
@testable import SportsKit

private func data(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Expected values read from each saved ESPN response.
struct LeagueFixture: Sendable, CustomTestStringConvertible {
    let league: League
    let games: Int
    let gameID: String
    let status: Game.Status
    let home: (String, Int)
    let away: (String, Int)
    let compactPeriod: String
    let plays: Int
    let scoringPlays: Int
    let teamStats: Int
    let boxScores: Int

    var testDescription: String { league.abbreviation }
}

private let fixtures: [LeagueFixture] = [
    .init(league: .cfb, games: 17, gameID: "401858274", status: .final, home: ("MIA", 52), away: ("PITT", 23),
          compactPeriod: "Q4", plays: 186, scoringPlays: 12, teamStats: 15, boxScores: 20),
    .init(league: .nba, games: 12, gameID: "401898406", status: .final, home: ("ORL", 136), away: ("MIA", 115),
          compactPeriod: "Q4", plays: 515, scoringPlays: 131, teamStats: 25, boxScores: 2),
    .init(league: .wnba, games: 1, gameID: "401918307", status: .final, home: ("ATL", 97), away: ("GS", 71),
          compactPeriod: "Q4", plays: 426, scoringPlays: 89, teamStats: 25, boxScores: 2),
    .init(league: .mlb, games: 1, gameID: "401908028", status: .live, home: ("TB", 5), away: ("CLE", 3),
          compactPeriod: "Top 8th", plays: 490, scoringPlays: 6, teamStats: 13, boxScores: 4),
    .init(league: .nhl, games: 4, gameID: "401892535", status: .final, home: ("NYR", 5), away: ("ANA", 2),
          compactPeriod: "P3", plays: 311, scoringPlays: 7, teamStats: 14, boxScores: 8),
    .init(league: .epl, games: 1, gameID: "401879257", status: .final, home: ("TOT", 3), away: ("COV", 1),
          compactPeriod: "FT", plays: 34, scoringPlays: 4, teamStats: 28, boxScores: 2),
    .init(league: .ucl, games: 9, gameID: "401915394", status: .final, home: ("AVL", 3), away: ("VFK", 1),
          compactPeriod: "FT", plays: 26, scoringPlays: 4, teamStats: 28, boxScores: 2),
    .init(league: .mls, games: 1, gameID: "761773", status: .final, home: ("CIN", 2), away: ("DC", 1),
          compactPeriod: "FT", plays: 22, scoringPlays: 3, teamStats: 28, boxScores: 2),
]

@Suite struct LeagueFixtureTests {
    @Test(arguments: fixtures)
    func decodesScoreboard(_ f: LeagueFixture) throws {
        let games = try ESPNProvider.parseScoreboard(data("\(f.league.id)-scoreboard"), leagueID: f.league.id)
        #expect(games.count == f.games)
        let game = try #require(games.first { $0.id == f.gameID })
        #expect(game.status == f.status)
        #expect(game.home.team.abbreviation == f.home.0)
        #expect(game.home.score == f.home.1)
        #expect(game.away.team.abbreviation == f.away.0)
        #expect(game.away.score == f.away.1)
        #expect(game.league == f.league)
        #expect(game.compactPeriod == f.compactPeriod)
    }

    @Test(arguments: fixtures)
    func decodesSummary(_ f: LeagueFixture) throws {
        let detail = try ESPNProvider.parseSummary(data("\(f.league.id)-summary"))
        #expect(detail.plays.count == f.plays)
        #expect(detail.plays.filter(\.isScoring).count == f.scoringPlays)
        #expect(detail.teamStats.count == f.teamStats)
        #expect(detail.boxScores.count == f.boxScores)
        #expect(detail.boxScores.allSatisfy { !$0.labels.isEmpty && !$0.title.isEmpty })
    }

    @Test func mlbTeamStatsComeFromTheGroups() throws {
        let stats = try ESPNProvider.parseSummary(data("mlb-summary")).teamStats
        #expect(stats.first?.label == "Hits")
        #expect(stats.first { $0.label == "Errors" } != nil)
    }

    @Test func soccerBoxScoreComesFromTheLineups() throws {
        let box = try #require(ESPNProvider.parseSummary(data("epl-summary")).boxScores.first)
        #expect(box.labels.prefix(5) == ["POS", "G", "A", "SH", "ST"])
        #expect(box.key?.contains("ST on target") == true)
        // Eleven starters plus the subs who came on, never the unused bench.
        #expect(box.rows.count == 16)
    }

    @Test func soccerHalfScoresComeFromTheSummary() throws {
        // The scoreboard has no half-by-half scores for soccer; the summary's header does.
        let detail = try ESPNProvider.parseSummary(data("epl-summary"), leagueID: League.epl.id)
        #expect(detail.periodScores == ["367": [1, 2], "388": [0, 1]])
    }

    @Test func soccerShotsComeFromTheCommentary() throws {
        let shots = try ESPNProvider.parseSummary(data("epl-summary"), leagueID: League.epl.id).shots
        let count = Dictionary(grouping: shots, by: \.outcome).mapValues(\.count)
        #expect(count == [.goal: 4, .save: 2, .offTarget: 14, .block: 8])
        #expect(Set(shots.map(\.teamID)) == ["367", "388"])
        // Headers, volleys and penalties count as goals; the own goal isn't a shot.
        let ucl = try ESPNProvider.parseSummary(data("ucl-summary"), leagueID: League.ucl.id).shots
        #expect(ucl.filter { $0.outcome == .goal }.count == 3)
        // Each shot carries its half, its shooter and where it ended (for the goal line).
        let barkley = try #require(ucl.first { $0.outcome == .goal && $0.shooter == "Ross Barkley" })
        #expect(barkley.period == 1)
        #expect(barkley.end == .init(x: 1.0, y: 0.52))
    }

    @Test func collegeGamesCarryPollRanks() throws {
        let games = try ESPNProvider.parseScoreboard(data("cfb-scoreboard"), leagueID: League.cfb.id)
        let game = try #require(games.first { $0.id == "401858274" })
        #expect(game.home.rankedName == "#1 Miami")
        // ESPN's 99 means unranked.
        #expect(game.away.rank == nil)
        #expect(game.away.rankedName == "Pitt")
    }

    @Test func datedCollegeScoreboardKeepsOnlyRankedTeamsGames() throws {
        // ESPN sends all 44 games for a date; 17 have a Top 25 team.
        let games = try ESPNProvider.parseScoreboard(data("cfb-scoreboard-day"), leagueID: League.cfb.id)
        #expect(games.count == 17)
        #expect(games.allSatisfy { $0.away.rank != nil || $0.home.rank != nil })
    }

    @Test func footballPlayTextDropsESPNClockAndFooter() throws {
        // College plays read "(15:00) #22 J.Weinberg kickoff…", some ending ", End Of Play"; the clock is shown separately.
        let plays = try ESPNProvider.parseSummary(data("cfb-summary"), leagueID: League.cfb.id).plays
        #expect(plays.first?.text.hasPrefix("#22 J.Weinberg kickoff") == true)
        #expect(!plays.contains { $0.text.hasPrefix("(1") || $0.text.hasPrefix("(0") || $0.text.hasSuffix("End Of Play") })
        // The NFL's formation notes are part of the play and stay.
        let nfl = try ESPNProvider.parseSummary(data("nfl-summary-final"), leagueID: League.nfl.id).plays
        #expect(nfl.contains { $0.text.hasPrefix("(Shotgun)") })
    }

    @Test func collegeStandingsAreTheAPPoll() throws {
        let poll = try ESPNProvider.parseRankings(data("cfb-rankings"))
        let table = try #require(poll.groups.first)
        #expect(poll.groups.count == 1)
        #expect(table.entries.count == 25)
        #expect(table.entries.first?.team.displayName == "Miami Hurricanes")
        #expect(table.entries.first?.values.first == "6-0")
    }

    @Test func everyKnownLeagueHasAnESPNMapping() async {
        #expect(await ESPNProvider().leagues() == League.all)
    }
}

@Suite struct PeriodNamingTests {
    @Test func labels() {
        #expect(League.nfl.periodLabel(4) == "4")
        #expect(League.nfl.periodLabel(5) == "OT")
        #expect(League.nba.periodLabel(6) == "2OT")
        #expect(League.nhl.periodLabel(4) == "OT")
        #expect(League.mlb.periodLabel(11) == "11")
        #expect(League.epl.periodLabel(3) == "ET")
    }

    @Test func titles() {
        #expect(League.nfl.periodTitle(3) == "Quarter 3")
        #expect(League.nhl.periodTitle(2) == "Period 2")
        #expect(League.nhl.periodTitle(4) == "Overtime")
        #expect(League.mlb.periodTitle(7) == "Inning 7")
        #expect(League.epl.periodTitle(1) == "First Half")
        #expect(League.epl.periodTitle(2) == "Second Half")
    }

    @Test func alertsOnlyWhereTheyMakeSense() {
        #expect(NotificationEvent.periodEnd.applies(to: .nhl))
        #expect(!NotificationEvent.periodEnd.applies(to: .mlb))
        #expect(!NotificationEvent.periodEnd.applies(to: .epl))
        #expect(NotificationEvent.halftime.applies(to: .epl))
        #expect(!NotificationEvent.halftime.applies(to: .nhl))
        #expect(NotificationEvent.closeGame.applies(to: .nba))
        #expect(!NotificationEvent.closeGame.applies(to: .epl))
        #expect(!NotificationEvent.redZone.applies(to: .nba))
    }
}

@Suite struct StandingsTests {
    private func standings(_ league: League) throws -> Standings {
        let url = try #require(Bundle.module.url(forResource: "\(league.id)-standings", withExtension: "json", subdirectory: "Fixtures"))
        return try ESPNProvider.parseStandings(Data(contentsOf: url), spec: try #require(ESPNEndpoints.standingsSpecs[league.id]))
    }

    @Test func nflSplitsIntoDivisions() throws {
        let table = try standings(.nfl)
        #expect(table.columns == ["W", "L", "T", "PCT"])
        #expect(table.groups.count == 8)
        let east = try #require(table.groups.first { $0.name == "AFC East" })
        #expect(east.entries.map(\.team.abbreviation) == ["BUF", "NE", "NYJ", "MIA"])
        #expect(east.entries.first?.values == ["5", "1", "0", ".833"])
        #expect(east.entries.first?.team.logoURL != nil)
    }

    @Test func soccerTables() throws {
        let mls = try standings(.mls)
        #expect(mls.columns == ["GP", "W", "D", "L", "GD", "PTS"])
        #expect(mls.groups.map(\.entries.count) == [15, 15])
        // The Champions League's league phase is one 36-team table.
        #expect(try standings(.ucl).groups.map(\.entries.count) == [36])
    }

    @Test func nbaIsRankedByWinPercentage() throws {
        let east = try #require(try standings(.nba).groups.first)
        #expect(east.name == "Eastern Conference")
        #expect(east.entries.count == 15)
        #expect(east.entries.prefix(3).map(\.team.abbreviation) == ["BOS", "ATL", "DET"])
    }

    @Test func eplIsRankedByPointsThenGoalDifference() throws {
        let table = try standings(.epl)
        #expect(table.columns == ["GP", "W", "D", "L", "GD", "PTS"])
        #expect(table.groups.first?.entries.prefix(2).map(\.team.abbreviation) == ["MNC", "ARS"])
    }

    @Test func everyLeagueHasAStandingsSpec() {
        // College football shows the AP poll instead (see collegeStandingsAreTheAPPoll).
        #expect(League.all.filter { $0 != .cfb }.allSatisfy { ESPNEndpoints.standingsSpecs[$0.id] != nil })
    }
}

@Suite struct DriveAndFieldTests {
    @Test func drivesCarrySummariesAndPlaySpots() throws {
        let url = try #require(Bundle.module.url(forResource: "nfl-summary-live", withExtension: "json", subdirectory: "Fixtures"))
        let detail = try ESPNProvider.parseSummary(Data(contentsOf: url))
        let drive = try #require(detail.drives.last)
        #expect(drive.summary == "6 plays, 35 yards, 3:56")
        #expect(drive.teamID == "25")
        #expect(detail.drives.flatMap(\.plays).count == detail.plays.count)
        let play = try #require(drive.plays.last)
        #expect(play.type == "Penalty")
        #expect(play.spot == "3rd & 1 at WSH 24")
        #expect(play.startYardLine == 76) // SF, the home team, at the WSH 24
        #expect(play.endYardLine == 66)   // pushed back to the WSH 34 by the penalty
    }

    @Test func liveSituationHasFieldPosition() throws {
        let url = try #require(Bundle.module.url(forResource: "nfl-scoreboard-live", withExtension: "json", subdirectory: "Fixtures"))
        let game = try #require(try ESPNProvider.parseScoreboard(Data(contentsOf: url), leagueID: "nfl").first { $0.id == "401873008" })
        #expect(game.situation?.yardLine == 31)
        #expect(game.situation?.distance == 10)
        #expect(game.situation?.shortDownAndDistance == "1st & 10 · SF 31")
    }

    @Test func playoffNoteAndSeries() throws {
        let url = try #require(Bundle.module.url(forResource: "mlb-scoreboard", withExtension: "json", subdirectory: "Fixtures"))
        let game = try #require(try ESPNProvider.parseScoreboard(Data(contentsOf: url), leagueID: "mlb").first)
        #expect(game.note == "ALCS - Game 6")
        #expect(game.seriesSummary == "TB leads series 3-2")
    }
}

@Suite struct OverviewTests {
    private func overview() throws -> GameOverview {
        let url = try #require(Bundle.module.url(forResource: "nfl-summary-upcoming", withExtension: "json", subdirectory: "Fixtures"))
        return try ESPNProvider.parseSummary(Data(contentsOf: url)).overview
    }

    @Test func venueAndBroadcast() throws {
        let o = try overview()
        #expect(o.venue?.name == "Mercedes-Benz Stadium")
        #expect(o.venue?.place == "Atlanta, GA")
        #expect(o.venue?.imageURL != nil)
        #expect(o.broadcasts == ["Fox"])
    }

    @Test func oddsAreAveragedAcrossBooks() throws {
        let odds = try #require(try overview().odds)
        #expect(odds.books == ["DraftKings"])
        #expect(odds.homeSpread == 3.5) // ATL +3.5, so SF favoured by 3.5
        #expect(odds.overUnder == 49.5)
        #expect(odds.homeMoneyLine == 170)
        #expect(odds.awayMoneyLine == -205)
    }

    @Test func standingsWinChanceAndLeaders() throws {
        let o = try overview()
        let sf = try #require(o.standings.first { $0.teamID == "25" })
        #expect(sf.group == "NFC West")
        #expect(sf.position == 1)
        #expect(o.standings.first { $0.teamID == "1" }?.position == 2)
        #expect(o.winProbability["25"] == 79.4)
        #expect(o.leaders.contains { $0.teamID == "25" && $0.athlete == "Brock Purdy" })
    }

    @Test func weatherAtKickoff() throws {
        let url = try #require(Bundle.module.url(forResource: "open-meteo", withExtension: "json", subdirectory: "Fixtures"))
        let kickoff = Date(timeIntervalSince1970: 1_792_947_600) // 2026-10-25T17:00Z
        let weather = try #require(try OpenMeteo.parse(Data(contentsOf: url), at: kickoff))
        #expect(weather.temperature.value == 19.2)
        #expect(weather.code == 1)
        #expect(weather.summary == "Partly cloudy")
        #expect(weather.windSpeed?.value == 15.4)
        #expect(weather.precipitationChance == 0)
    }
}

@Suite struct ProbabilityTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    private func points() throws -> [ChartPoint] {
        let probabilities = try ESPNProvider.parseProbabilities(fixture("nfl-probabilities"))
        let plays = try ESPNProvider.parseSummary(fixture("nfl-summary-wshsf")).plays
        return Probability.chart(probabilities, plays: plays, league: .nfl)
    }

    @Test func basketballLastMinuteClocksStayInOrder() {
        func play(_ id: String, _ period: Int, _ clock: String) -> Play {
            Play(id: id, text: "", period: period, clock: clock, teamID: nil, isScoring: false, awayScore: 0, homeScore: 0)
        }
        // NBA shows plain seconds in a quarter's last minute; "--" is a play with no usable clock.
        let plays = [play("a", 1, "1:05"), play("b", 1, "45.3"), play("c", 1, "--"), play("d", 2, "11:40"), play("e", 1, "0.0")]
        let points = plays.map { ProbabilityPoint(playID: $0.id, homeWin: 0.5, homeCover: nil, over: nil) }
        let chart = Probability.chart(points, plays: plays, league: .nba)
        #expect(chart.map(\.playID) == ["a", "b", "e", "d"]) // "c" dropped, "e" placed by its clock, not its feed position
        #expect(zip(chart, chart.dropFirst()).allSatisfy { $0.progress <= $1.progress })
        #expect(abs(chart[1].progress - (1 - (45.3 + 3 * 720) / 2880)) < 0.0001)
    }

    @Test func parsesEveryPlayWithCoverAndOver() throws {
        let probabilities = try ESPNProvider.parseProbabilities(fixture("nfl-probabilities"))
        #expect(probabilities.count == 179)
        #expect(probabilities.first?.playID == "4018730081")
        #expect(probabilities.first?.homeWin == 0.8701)
        #expect(probabilities.last?.homeWin == 1.0)
        #expect(probabilities.allSatisfy { $0.homeCover != nil && $0.over != nil })
    }

    @Test func chartRunsFromKickoffToFullTime() throws {
        let chart = try points()
        #expect(chart.count >= 170)
        #expect(chart.first!.progress < 0.01)
        #expect(chart.last!.progress == 1)
        #expect(chart.last!.secondsLeft == 0)
        #expect(zip(chart, chart.dropFirst()).allSatisfy { $0.progress <= $1.progress + 0.0001 })
        #expect(chart.last!.homeScore == 23 && chart.last!.awayScore == 17)
    }

    @Test func marketLineUsesESPNAndOtherLinesShiftTheRightWay() throws {
        let chart = try points()
        let mid = chart[chart.count / 2]
        let market = try #require(Probability.homeCover(at: mid, line: -7.5, marketLine: -7.5, league: .nfl, final: true))
        #expect(market == mid.homeCover)
        // Giving the home team more points makes covering likelier; fewer, less likely.
        let easier = try #require(Probability.homeCover(at: mid, line: -3.5, marketLine: -7.5, league: .nfl, final: true))
        let harder = try #require(Probability.homeCover(at: mid, line: -10.5, marketLine: -7.5, league: .nfl, final: true))
        #expect(easier > market && harder < market)
        let higherTotal = try #require(Probability.over(at: mid, total: 55.5, marketTotal: 51.5, league: .nfl, final: true))
        #expect(higherTotal < mid.over!)
    }

    @Test func fullTimeSettlesOnTheFinalScore() throws {
        let last = try #require(try points().last) // SF won 23-17, a 6-point margin
        #expect(Probability.homeCover(at: last, line: -7.5, marketLine: -7.5, league: .nfl, final: true) == 0)
        #expect(Probability.homeCover(at: last, line: -5.5, marketLine: -7.5, league: .nfl, final: true) == 1)
        #expect(Probability.homeCover(at: last, line: -6, marketLine: -7.5, league: .nfl, final: true) == 0.5)
        #expect(Probability.over(at: last, total: 39.5, marketTotal: 51.5, league: .nfl, final: true) == 1)
    }

    @Test func normalMathRoundTrips() {
        for p in [0.01, 0.2, 0.5, 0.8, 0.99] {
            #expect(abs(Probability.normalCDF(Probability.inverseNormalCDF(p)) - p) < 1e-6)
        }
    }

    @Test func gameLeadersCarryHeadshotsAndMainStat() throws {
        let leaders = try ESPNProvider.parseSummary(fixture("nfl-summary-wshsf")).overview.leaders
        let purdy = try #require(leaders.first { $0.athlete == "Brock Purdy" })
        #expect(purdy.shortName == "B. Purdy")
        #expect(purdy.position == "QB")
        #expect(purdy.mainValue == "264")
        #expect(purdy.summary == "21/29, 1 TD")
        #expect(purdy.headshotURL != nil)
    }
}

@Suite struct PlaySurfaceTests {
    private func detail(_ league: League) throws -> GameDetail {
        let url = try #require(Bundle.module.url(forResource: "\(league.id)-summary", withExtension: "json", subdirectory: "Fixtures"))
        return try ESPNProvider.parseSummary(Data(contentsOf: url), leagueID: league.id)
    }

    @Test func basketballShotsLandOnTheHalfCourt() throws {
        let plays = try detail(.nba).plays
        let layup = try #require(plays.first { $0.text.hasPrefix("Franz Wagner makes driving layup") })
        #expect(layup.isShot)
        let expected = Play.Location(x: 23.0 / 50, y: 3.0 / 47) // 3 ft out, near the middle
        #expect(layup.location == expected)
        // The jump ball has ESPN's "no spot" sentinel and gets no location.
        #expect(plays.first?.location == nil)
        let spots: [Play.Location] = plays.compactMap(\.location)
        let inside = spots.allSatisfy { spot in spot.x >= 0 && spot.x <= 1 && spot.y >= 0 && spot.y <= 1 }
        #expect(inside)
    }

    @Test func hockeyUsesTheWholeRink() throws {
        let located: [Play.Location] = try detail(.nhl).plays.compactMap(\.location)
        #expect(located.count > 250)
        let left = located.contains { spot in spot.x < 0.1 }, right = located.contains { spot in spot.x > 0.9 }
        #expect(left && right) // both ends
    }

    @Test func baseballHitsAndSoccerGoalsHaveSpots() throws {
        let hits = try detail(.mlb).plays.filter { $0.location != nil }
        #expect(hits.count == 132)
        let firstHit = Play.Location(x: 119.0 / 250, y: 125.0 / 250)
        #expect(hits.first?.location == firstHit)
        let goals = try detail(.epl).plays.filter { $0.location != nil }
        #expect(goals.count == 4)
        let nearGoal = goals.allSatisfy { goal in (goal.location?.x ?? 0) > 0.75 } // scored near the attacked goal
        #expect(nearGoal)
    }

    @Test func liveBaseballSituation() throws {
        let url = try #require(Bundle.module.url(forResource: "mlb-scoreboard", withExtension: "json", subdirectory: "Fixtures"))
        let game = try #require(try ESPNProvider.parseScoreboard(Data(contentsOf: url), leagueID: "mlb").first)
        let state = try #require(game.situation?.baseball)
        #expect(state.balls == 0 && state.strikes == 1 && state.outs == 2)
        #expect(state.onFirst && state.onSecond && state.onThird)
    }
}
