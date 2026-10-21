import Foundation
import Testing
@testable import SportsKit

private func detail(_ name: String) throws -> GameDetail {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try ESPNProvider.parseSummary(Data(contentsOf: url))
}

@Suite struct ESPNSummaryTests {
    @Test func decodesFinalGamePlays() throws {
        let plays = try detail("nfl-summary-final").plays
        #expect(plays.count == 178)
        #expect(plays.first?.id == "40187300639")
        #expect(plays.first?.period == 1)
        #expect(plays.first?.clock == "15:00")
        #expect(plays.last?.text == "END GAME")
        #expect(plays.last?.awayScore == 6) // LAC
        #expect(plays.last?.homeScore == 22) // KC
        #expect(plays.filter(\.isScoring).count == 7)
        #expect(plays.allSatisfy { $0.teamID != nil })
    }

    @Test func liveDriveIsNotDuplicated() throws {
        let plays = try detail("nfl-summary-live").plays
        #expect(Set(plays.map(\.id)).count == plays.count)
        #expect(plays.last?.id == "4018730081645")
        #expect(plays.last?.period == 2)
    }

    @Test func decodesBoxScore() throws {
        let boxScores = try detail("nfl-summary-final").boxScores
        #expect(boxScores.count == 20) // 10 categories × 2 teams
        let passing = try #require(boxScores.first { $0.category == "passing" })
        #expect(passing.title == "Los Angeles Passing")
        #expect(passing.labels == ["C/ATT", "YDS", "AVG", "TD", "INT", "SACKS", "QBR", "RTG"])
        #expect(passing.rows.first?.name == "Justin Herbert")
        #expect(passing.rows.first?.stats.first == "22/37")
    }

    @Test func decodesTeamStatsAwayAndHome() throws {
        let stats = try detail("nfl-summary-final").teamStats
        #expect(stats.count == 25)
        #expect(stats.first?.label == "1st Downs")
        #expect(stats.first?.away == "15") // LAC
        #expect(stats.first?.home == "22") // KC
    }

    @Test func scheduledGameHasNoPlaysOrBoxScore() throws {
        let detail = try detail("nfl-summary-scheduled")
        #expect(detail.plays.isEmpty)
        #expect(detail.boxScores.isEmpty)
    }
}

@Test func courtSituationParsesTimeoutsFoulsAndBonus() throws {
    let json = #"{"homeTimeouts":{"timeoutsCurrent":1,"timeoutsRemainingCurrent":0},"awayTimeouts":{"timeoutsCurrent":4},"homeFouls":{"teamFoulsCurrent":6,"bonusState":"DOUBLE"},"awayFouls":{"teamFoulsCurrent":2,"bonusState":"NONE"}}"#
    let court = try ESPNProvider.parseCourtSituation(Data(json.utf8))
    #expect(court.home == .init(timeoutsLeft: 1, fouls: 6, inBonus: true))
    #expect(court.away == .init(timeoutsLeft: 4, fouls: 2, inBonus: false))
    let football = try ESPNProvider.parseCourtSituation(Data(#"{"down":0,"homeTimeouts":2,"awayTimeouts":0}"#.utf8))
    #expect(football.home == .init(timeoutsLeft: 2, fouls: nil, inBonus: false))
    #expect(football.away.timeoutsLeft == 0)
}

@Test func basketballPossessionFollowsThePlays() {
    func play(_ type: String, _ team: String?, scoring: Bool = false, shot: Bool = false) -> Play {
        Play(id: type, text: "", period: 1, clock: "", teamID: team, isScoring: scoring, awayScore: 0, homeScore: 0, type: type, isShot: shot)
    }
    func ball(_ plays: Play...) -> String? { CourtSituation.possession(after: plays, awayID: "A", homeID: "H") }
    #expect(ball(play("Jump Shot", "A", scoring: true, shot: true)) == "H")
    #expect(ball(play("Jump Shot", "A", shot: true)) == "A")
    #expect(ball(play("Jump Shot", "A", shot: true), play("Defensive Rebound", "H")) == "H")
    #expect(ball(play("Lost Ball Turnover", "H"), play("Substitution", "H"), play("Full Timeout", "A")) == "A")
    #expect(ball(play("Shooting Foul", "H"), play("Free Throw - 1 of 2", "A", scoring: true)) == "A")
    #expect(ball(play("Free Throw - 2 of 2", "A", scoring: true)) == "H")
    #expect(ball(play("Free Throw - 2 of 2", "A")) == "A")
    #expect(ball(play("Personal Foul", "H")) == "A")
    #expect(ball(play("Jump Shot", "A", scoring: true, shot: true), play("End Period", nil)) == nil)
}

@Test func hockeySituationAndPowerPlayTeam() throws {
    let court = try ESPNProvider.parseCourtSituation(Data(#"{"powerPlay":true,"emptyNet":false}"#.utf8))
    #expect(court.powerPlay && !court.emptyNet && court.home.timeoutsLeft == nil)
    let penalty = Play(id: "1", text: "Jakub Dobes Interference against Collin Graf served by Alex Newhook", period: 3, clock: "",
                       teamID: "10", isScoring: false, awayScore: 0, homeScore: 0)
    #expect(CourtSituation.powerPlayTeam(after: [penalty], awayID: "10", homeID: "18") == "18")
}

@Test func baseballPlayResultTakesItsOutcome() throws {
    let json = #"{"plays":[{"id":"1","type":{"text":"Single"},"text":"Pitch 5 : Ball In Play","team":{"id":"30"}},{"id":"2","type":{"text":"Play Result"},"text":"Kwan reached on infield single to shortstop.","team":{"id":"5"}}]}"#
    let detail = try ESPNProvider.parseSummary(Data(json.utf8), leagueID: League.mlb.id)
    #expect(detail.plays.last?.headline == "Single")
    #expect(detail.plays.first?.headline == nil)
}
