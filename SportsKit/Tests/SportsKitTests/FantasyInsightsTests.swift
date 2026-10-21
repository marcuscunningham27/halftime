import Foundation
import Testing
@testable import SportsKit

@Suite struct FantasyInsightsTests {
    @Test func holesUseBestAssignment() {
        // TE fills TE, so the RB-WR-TE FLEX goes to the spare WR rather than leaving TE empty.
        #expect(ByeWeekPlanner.holes(slots: ["QB", "RB", "WR", "TE", "FLEX"], available: ["QB", "RB", "WR", "WR", "TE"]) == 0)
        #expect(ByeWeekPlanner.holes(slots: ["QB", "RB", "WR", "TE", "FLEX", "K", "DEF"], available: ["QB", "RB", "WR", "TE", "TE"]) == 2)
        #expect(ByeWeekPlanner.holes(slots: ["SUPER_FLEX", "QB"], available: ["QB"]) == 1)
        #expect(ByeWeekPlanner.holes(slots: ["RB", "RB", "FLEX"], available: ["RB", "WR"]) == 1)
    }

    @Test func seasonTrendGaps() {
        let weeks = [
            FantasyWeekResult(week: 1, starters: [qb(25, 18), rb(5, 10)]),
            FantasyWeekResult(week: 2, starters: [qb(20, 19), rb(8, 9)]),
        ]
        let trend = SeasonTrend(weeks: weeks)
        #expect(trend.actualPerWeek == 29 && trend.projectedPerWeek == 28 && trend.gapPerWeek == 1)
        #expect(trend.gapByPosition.map(\.position) == ["RB", "QB"])
        #expect(trend.gapByPosition.first?.gap == -3)
        #expect(trend.gapByStarter.map(\.gap) == [-6, 8])
        #expect(trend.gapByStarter.map(\.name) == ["Runner", "Passer"])
    }

    private func qb(_ actual: Double, _ projected: Double) -> FantasyWeekResult.Starter {
        .init(playerID: "qb", name: "Passer", position: "QB", actual: actual, projected: projected)
    }

    private func rb(_ actual: Double, _ projected: Double) -> FantasyWeekResult.Starter {
        .init(playerID: "rb", name: "Runner", position: "RB", actual: actual, projected: projected)
    }

    @Test func standingsRankByRecordThenPoints() {
        let standings = [
            FantasyStanding(id: "a", teamName: "A", wins: 3, losses: 2, ties: 0, pointsFor: 600, isMine: false),
            FantasyStanding(id: "b", teamName: "B", wins: 5, losses: 0, ties: 0, pointsFor: 500, isMine: true),
            FantasyStanding(id: "c", teamName: "C", wins: 3, losses: 2, ties: 0, pointsFor: 650, isMine: false),
        ]
        #expect(FantasyStanding.ranked(standings).map(\.id) == ["b", "c", "a"])
    }

    @Test func sleeperWeekResultAndCalendar() throws {
        let rosters = #"[{"roster_id":3,"owner_id":"me","settings":{"wins":2,"losses":4,"fpts":625,"fpts_decimal":56}}]"#
        let matchups = #"[{"roster_id":3,"starters":["4046","0","KC"],"starters_points":[19.3,0,4]}]"#
        let result = try #require(try Sleeper.parseWeekResult(rosters: Data(rosters.utf8), matchups: Data(matchups.utf8), userID: "me",
                                                              week: 3, projections: ["4046": 18],
                                                              players: ["4046": FantasyPlayer(id: "4046", name: "Patrick Mahomes", position: "QB",
                                                                                              team: "KC", espnID: nil, photoURL: nil)]))
        #expect(result.starters.first?.name == "Patrick Mahomes" && result.starters.last?.name == "KC")
        #expect(result.starters.map(\.playerID) == ["4046", "KC"])
        #expect(abs(result.actual - 23.3) < 0.001 && result.projected == 18)
        let standings = try Sleeper.parseStandings(rosters: Data(rosters.utf8), users: Data("[]".utf8), userID: "me")
        #expect(standings.first?.pointsFor == 625.56 && standings.first?.record == "2-4" && standings.first?.isMine == true)
        let calendar = try Sleeper.parseCalendar(Data(#"{"settings":{"playoff_week_start":15,"trade_deadline":11}}"#.utf8))
        #expect(calendar.playoffWeekStart == 15 && calendar.tradeDeadlineWeek == 11)
        #expect(try Sleeper.parseCalendar(Data(#"{"settings":{"trade_deadline":99}}"#.utf8)).tradeDeadlineWeek == nil)
    }

    @Test func sleeperInjuries() throws {
        let json = #"{"8110":{"full_name":"Jacory Croskey-Merritt","team":"WAS","position":"RB","injury_status":"Out","injury_body_part":"Groin","practice_participation":"DNP"}}"#
        let injury = try #require(try Sleeper.parsePlayers(Data(json.utf8))["8110"]?.injury)
        #expect(injury.status == "Out" && injury.detail == "Groin · DNP practice" && injury.severity == 3)
    }

    @Test func espnNewsParses() throws {
        let json = #"""
        {"feed":[{"id":1,"headline":"Mahomes threw for 272 yards.","story":"Analysis.","published":"2026-10-19T00:51:19Z","type":"Rotowire",
                  "links":{"mobile":{"href":"http://m.espn.go.com/wireless/story?storyId=1"}}},
                 {"id":2}]}
        """#
        let news = try ESPNNews.parse(Data(json.utf8))
        #expect(news.count == 1 && news[0].source == "Rotowire" && news[0].story == "Analysis.")
        #expect(news[0].url?.absoluteString == "https://m.espn.go.com/wireless/story?storyId=1")
    }

    @Test func byesAreWeeksATeamDoesntPlay() throws {
        let games = try ESPNProvider.parseScoreboard(Data(contentsOf: #require(Bundle.module.url(forResource: "nfl-scoreboard-live", withExtension: "json", subdirectory: "Fixtures"))), leagueID: League.nfl.id)
        let first = try #require(games.first)
        let byes = ESPNProvider.byes(in: [1: games, 2: Array(games.dropFirst())])
        #expect(byes[first.away.team.abbreviation] == 2 && byes[first.home.team.abbreviation] == 2)
        #expect(byes.count == 2)
    }

    @Test func espnRosterParses() throws {
        let json = #"{"athletes":[{"position":"offense","items":[{"id":"4595348","fullName":"Malik Nabers"}]},{"items":[]}]}"#
        #expect(try ESPNNews.parseRoster(Data(json.utf8)).map(\.id) == ["4595348"])
    }

    @Test func newsHTMLBecomesPlainText() {
        #expect(ESPNNews.plainText("<p><photo>12</photo>Who should   you start?</p><p>Rams &amp; Cardinals</p>") == "12 Who should you start? Rams & Cardinals")
    }

    @Test func weekPromptFlagsByesInjuriesAndEmptySlots() {
        let allen = FantasyPlayer(id: "1", name: "Josh Allen", position: "QB", team: "BUF", espnID: nil, photoURL: nil)
        let jcm = FantasyPlayer(id: "2", name: "Jacory Croskey-Merritt", position: "RB", team: "WSH", espnID: nil, photoURL: nil,
                                injury: .init(status: "IR", detail: "Groin"))
        let mahomes = FantasyPlayer(id: "3", name: "Patrick Mahomes", position: "QB", team: "KC", espnID: nil, photoURL: nil)
        let team = FantasyTeam(lineup: [.init(label: "QB", player: allen), .init(label: "RB", player: jcm), .init(label: "RB", player: nil)],
                               bench: [mahomes])
        let prompt = FantasyPrompt.week(team: team, week: 7, matchup: nil, projections: ["3": 18.2], byes: ["BUF": 7, "KC": 5], news: [:])
        #expect(prompt.contains("- QB: Josh Allen (BUF QB), ON BYE this week"))
        #expect(prompt.contains("status IR (Groin)"))
        #expect(prompt.contains("- RB: EMPTY"))
        #expect(prompt.contains("- Patrick Mahomes (KC QB), projected 18.2"))
        #expect(prompt.contains("- QB: Josh Allen is on bye; bench options: Patrick Mahomes (18.2)"))
        #expect(prompt.contains("- RB: Jacory Croskey-Merritt is out; bench options: none"))
        #expect(prompt.contains("- RB: empty; bench options: none"))
    }

    @Test func coverKeepsStartersAndFillsGapsFromBench() {
        func player(_ id: String, _ position: String) -> FantasyPlayer {
            FantasyPlayer(id: id, name: id, position: position, team: "X", espnID: nil, photoURL: nil)
        }
        let allen = player("Allen", "QB"), harvey = player("Harvey", "RB"), kraft = player("Kraft", "TE")
        let goedert = player("Goedert", "TE"), mahomes = player("Mahomes", "QB"), lemon = player("Lemon", "WR")
        let lineup: [FantasyTeam.Slot] = [.init(label: "QB", player: allen), .init(label: "RB", player: harvey),
                                          .init(label: "TE", player: kraft), .init(label: "FLEX", player: goedert),
                                          .init(label: "DEF", player: nil)]
        // Allen and Kraft are out: Mahomes takes QB; Goedert should slide FLEX→TE so Lemon can take FLEX.
        let cover = LineupCover(lineup: lineup, bench: [mahomes, lemon]) { ![allen, kraft].contains($0) }
        #expect(cover.slots.map { $0.filledBy?.id } == ["Mahomes", "Harvey", "Goedert", "Lemon", nil])
        #expect(cover.holes == 1)
        #expect(cover.changes.map(\.label) == ["QB", "TE", "FLEX", "DEF"])
        let clear = LineupCover(lineup: Array(lineup.prefix(4)), bench: []) { _ in true }
        #expect(clear.changes.isEmpty && clear.holes == 0)
    }

    @Test func coverDoesNotMoveStartersNeedlessly() {
        func player(_ id: String, _ position: String) -> FantasyPlayer {
            FantasyPlayer(id: id, name: id, position: position, team: "X", espnID: nil, photoURL: nil)
        }
        let harvey = player("Harvey", "RB"), najee = player("Najee", "RB")
        let cover = LineupCover(lineup: [.init(label: "RB", player: harvey), .init(label: "RB", player: nil)], bench: [najee]) { _ in true }
        #expect(cover.slots.map { $0.filledBy?.id } == ["Harvey", "Najee"])
        #expect(cover.changes.count == 1)
    }
}

@Test func fantasyRosterFindsPlayersInPlaysAndBoxScores() {
    func player(_ name: String, espn: String? = nil) -> FantasyPlayer {
        FantasyPlayer(id: name, name: name, position: nil, team: nil, espnID: espn, photoURL: nil)
    }
    let roster = FantasyRoster(players: [player("Jayden Daniels", espn: "4426348"), player("Christian McCaffrey"),
                                         player("Amon-Ra St. Brown"), player("Marvin Harrison Jr.")])
    #expect(FantasyRoster.shortName("Marvin Harrison Jr.") == "M.Harrison")
    let pass = "(Shotgun) J.Daniels pass deep middle to A.Williams to SF 28 for 17 yards"
    #expect(roster.players(in: pass).map(\.name) == ["Jayden Daniels"])
    #expect(roster.players(in: "L.McCaffrey right end to WAS 12").isEmpty)
    #expect(roster.players(in: "C.McCaffrey up the middle").map(\.name) == ["Christian McCaffrey"])
    #expect(roster.players(in: "pass to A.St. Brown for 9 yards").map(\.name) == ["Amon-Ra St. Brown"])
    #expect(roster.players(in: "AJ.Daniels runs").isEmpty)
    #expect(roster.players(in: "M.Harrison catches it").map(\.name) == ["Marvin Harrison Jr."])
    #expect(roster.contains(athleteID: "4426348", name: "Jayden Daniels"))
    #expect(!roster.contains(athleteID: "1", name: "Brock Purdy"))
}
