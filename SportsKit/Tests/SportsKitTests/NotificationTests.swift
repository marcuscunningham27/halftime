import Foundation
import SwiftData
import Testing
@testable import SportsKit

// MARK: - Snapshot builders

private let kc = Team(id: "12", abbreviation: "KC", displayName: "Kansas City Chiefs", shortName: "Chiefs",
                      colorHex: nil, alternateColorHex: nil, logoURL: nil)
private let buf = Team(id: "2", abbreviation: "BUF", displayName: "Buffalo Bills", shortName: "Bills",
                       colorHex: nil, alternateColorHex: nil, logoURL: nil)

/// KC at BUF. Defaults describe a quiet moment mid-game.
private func snap(_ status: Game.Status = .live, away: Int? = 7, home: Int? = 3, period: Int = 2, clock: String = "8:00",
                  intermission: Game.Intermission? = nil, possession: Team.ID? = nil, redZone: Bool = false,
                  league: League.ID = "nfl") -> Game {
    Game(id: "g1", leagueID: league, startDate: .now, status: status, period: period, clock: clock,
         statusDetail: "detail", home: .init(team: buf, score: status == .scheduled ? nil : home, periodScores: []),
         away: .init(team: kc, score: status == .scheduled ? nil : away, periodScores: []),
         intermission: intermission,
         situation: possession.map { .init(possessionTeamID: $0, isRedZone: redZone, downAndDistance: "1st & 10 at BUF 18") })
}

private func types(_ old: Game, _ new: Game) -> [NotificationEvent] {
    var detector = GameEventDetector()
    _ = detector.events(old: nil, new: old)
    return detector.events(old: old, new: new).map(\.type)
}

// MARK: - Detector

@Suite struct GameEventDetectorTests {
    @Test func gameStart() {
        #expect(types(snap(.scheduled), snap(away: 0, home: 0, period: 1, clock: "15:00")) == [.gameStart])
    }

    @Test func scoreUpdateWithoutLeadChange() {
        #expect(types(snap(away: 7, home: 3), snap(away: 14, home: 3)) == [.scoreUpdate])
    }

    @Test func leadChange() {
        #expect(types(snap(away: 7, home: 3), snap(away: 7, home: 10)) == [.scoreUpdate, .leadChange])
    }

    @Test func tyingIsNotALeadChange() {
        #expect(types(snap(away: 7, home: 3), snap(away: 7, home: 7)) == [.scoreUpdate])
    }

    @Test func periodEnd() {
        #expect(types(snap(period: 1, clock: "0:10"), snap(period: 1, clock: "0:00", intermission: .endOfPeriod)) == [.periodEnd])
    }

    @Test func halftime() {
        #expect(types(snap(clock: "0:10"), snap(clock: "0:00", intermission: .halftime)) == [.halftime])
    }

    @Test func overtime() {
        #expect(types(snap(away: 20, home: 20, period: 4, clock: "0:00"), snap(away: 20, home: 20, period: 5, clock: "10:00"))
            .contains(.overtime))
    }

    @Test func closeGameFiresOnceWhenItBecomesClose() {
        #expect(types(snap(away: 21, home: 17, period: 4, clock: "5:30"), snap(away: 21, home: 17, period: 4, clock: "4:59")) == [.closeGame])
        #expect(types(snap(away: 21, home: 17, period: 4, clock: "4:59"), snap(away: 21, home: 17, period: 4, clock: "4:30")).isEmpty)
        #expect(types(snap(away: 31, home: 17, period: 4, clock: "5:30"), snap(away: 31, home: 17, period: 4, clock: "4:59")).isEmpty)
    }

    @Test func final() {
        #expect(types(snap(period: 4, clock: "0:00"), snap(.final, period: 4, clock: "0:00")) == [.final])
    }

    @Test func nothingChanged() {
        #expect(types(snap(), snap(clock: "7:45")).isEmpty)
    }

    @Test func firstSightingOnlyRecordsState() {
        var detector = GameEventDetector()
        #expect(detector.events(old: nil, new: snap(.final)).isEmpty)
    }

    @Test func redZoneOncePerDriveWithSpecWording() throws {
        var detector = GameEventDetector()
        let start = snap(possession: kc.id, redZone: false)
        _ = detector.events(old: nil, new: start)
        let entered = snap(clock: "7:30", possession: kc.id, redZone: true)
        let event = try #require(detector.events(old: start, new: entered).first)
        #expect(event.type == .redZone)
        #expect(event.body == "Chiefs in the red zone: 1st and 10 at BUF 18")

        // Pushed back out by a penalty, then back in: same drive, no repeat.
        let out = snap(clock: "7:00", possession: kc.id, redZone: false)
        let backIn = snap(clock: "6:30", possession: kc.id, redZone: true)
        #expect(detector.events(old: entered, new: out).isEmpty)
        #expect(detector.events(old: out, new: backIn).isEmpty)

        // Bills get the ball, then the Chiefs drive back: new drive, alerts again.
        let turnover = snap(clock: "5:00", possession: buf.id, redZone: false)
        let nextDrive = snap(clock: "2:00", possession: kc.id, redZone: true)
        #expect(detector.events(old: backIn, new: turnover).isEmpty)
        #expect(detector.events(old: turnover, new: nextDrive).map(\.type) == [.redZone])
    }

    @Test func alreadyInRedZoneAtLaunchDoesNotAlert() {
        var detector = GameEventDetector()
        let first = snap(possession: kc.id, redZone: true)
        _ = detector.events(old: nil, new: first)
        #expect(detector.events(old: first, new: snap(clock: "7:40", possession: kc.id, redZone: true)).isEmpty)
    }
}

// MARK: - Preferences

private let chiefs = Follows.TeamRef(leagueID: "nfl", teamID: kc.id)
private let bills = Follows.TeamRef(leagueID: "nfl", teamID: buf.id)

@Suite struct NotificationRulesTests {
    @Test func unfollowedGamesNeverNotify() {
        let rules = NotificationRules(follows: Follows(leagueIDs: [], teams: []), mutedTeams: [], overrides: [])
        #expect(!rules.shouldNotify(.final, for: snap()))
    }

    @Test func followingUsesSpecDefaults() {
        let rules = NotificationRules(follows: Follows(leagueIDs: [], teams: [chiefs]), mutedTeams: [], overrides: [])
        for event in NotificationEvent.allCases {
            #expect(rules.shouldNotify(event, for: snap()) == event.isOnByDefault, "\(event)")
        }
    }

    @Test func teamOverridesLeagueOverridesGlobal() {
        let rules = NotificationRules(follows: Follows(leagueIDs: ["nfl"], teams: [chiefs]), mutedTeams: [], overrides: [
            (.global, .halftime, true),
            (.league("nfl"), .halftime, false),
            (.team(chiefs), .halftime, true),
            (.global, .final, false),
        ])
        #expect(rules.resolved(.halftime, at: .global))
        #expect(!rules.resolved(.halftime, at: .league("nfl")))
        #expect(rules.resolved(.halftime, at: .team(chiefs)))
        #expect(rules.resolved(.halftime, at: .team(bills)) == false) // falls back to league
        #expect(!rules.resolved(.final, at: .team(chiefs)))           // falls back to global
        #expect(rules.shouldNotify(.halftime, for: snap()))
    }

    @Test func mutedTeamIsSilentEvenInFollowedLeague() {
        let rules = NotificationRules(follows: Follows(leagueIDs: ["nfl"], teams: [chiefs]), mutedTeams: [chiefs], overrides: [])
        #expect(!rules.shouldNotify(.final, for: snap()))
    }

    @Test func eitherFollowedTeamCanAskForAnEvent() {
        let rules = NotificationRules(follows: Follows(leagueIDs: [], teams: [chiefs, bills]), mutedTeams: [chiefs],
                                      overrides: [(.team(bills), .final, true)])
        #expect(rules.shouldNotify(.final, for: snap()))
    }

    @Test func redZoneIsNFLOnly() {
        let rules = NotificationRules(follows: Follows(leagueIDs: ["nfl", "nba"], teams: []), mutedTeams: [],
                                      overrides: [(.global, .redZone, true)])
        #expect(rules.shouldNotify(.redZone, for: snap()))
        #expect(!rules.shouldNotify(.redZone, for: snap(league: "nba")))
    }

    /// Phase 5's bar: each toggle fires or silences its own event.
    @Test(arguments: NotificationEvent.allCases)
    func eachToggleFiresOrSilencesItsEvent(event: NotificationEvent) throws {
        let (old, new) = scenario(for: event)
        for isOn in [true, false] {
            let rules = NotificationRules(follows: Follows(leagueIDs: [], teams: [chiefs]), mutedTeams: [],
                                          overrides: [(.team(chiefs), event, isOn)])
            var detector = GameEventDetector()
            _ = detector.events(old: nil, new: old)
            let sent = detector.events(old: old, new: new).filter { rules.shouldNotify($0.type, for: new) }.map(\.type)
            #expect(sent.contains(event) == isOn, "\(event) toggle \(isOn)")
        }
    }

    private func scenario(for event: NotificationEvent) -> (Game, Game) {
        switch event {
        case .gameStart: (snap(.scheduled), snap(away: 0, home: 0, period: 1, clock: "15:00"))
        case .scoreUpdate: (snap(away: 7, home: 3), snap(away: 14, home: 3))
        case .leadChange: (snap(away: 7, home: 3), snap(away: 7, home: 10))
        case .periodEnd: (snap(period: 1), snap(period: 1, clock: "0:00", intermission: .endOfPeriod))
        case .halftime: (snap(), snap(clock: "0:00", intermission: .halftime))
        case .overtime: (snap(away: 20, home: 20, period: 4, clock: "0:00"), snap(away: 20, home: 20, period: 5, clock: "10:00"))
        case .closeGame: (snap(away: 21, home: 17, period: 4, clock: "5:30"), snap(away: 21, home: 17, period: 4, clock: "4:59"))
        case .final: (snap(period: 4, clock: "0:00"), snap(.final, period: 4, clock: "0:00"))
        case .redZone: (snap(possession: kc.id), snap(clock: "7:30", possession: kc.id, redZone: true))
        }
    }
}

// MARK: - Quiet hours

@Suite struct QuietHoursTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
    }

    @Test func overnightWindowHoldsUntilMorning() {
        let quiet = QuietHours(isEnabled: true, start: 22 * 60, end: 7 * 60)
        #expect(quiet.holdUntil(at(23), calendar: calendar) == calendar.date(byAdding: .hour, value: 8, to: at(23)))
        #expect(quiet.holdUntil(at(3), calendar: calendar) == at(7))
        #expect(quiet.holdUntil(at(12), calendar: calendar) == nil)
        #expect(quiet.holdUntil(at(7), calendar: calendar) == nil)
    }

    @Test func offByDefaultSendsNow() {
        #expect(QuietHours(isEnabled: false, start: 22 * 60, end: 7 * 60).holdUntil(at(23), calendar: calendar) == nil)
    }
}

// MARK: - ESPN mapping

@Suite struct ESPNSituationTests {
    @Test func liveGameCarriesSituation() throws {
        let url = try #require(Bundle.module.url(forResource: "nfl-scoreboard-live", withExtension: "json", subdirectory: "Fixtures"))
        let game = try #require(try ESPNProvider.parseScoreboard(Data(contentsOf: url), leagueID: "nfl").first { $0.id == "401873008" })
        #expect(game.situation?.possessionTeamID == "25")
        #expect(game.situation?.isRedZone == false)
        #expect(game.situation?.downAndDistance == "1st & 10 at SF 31")
        #expect(game.intermission == nil)
    }

    @Test(arguments: [("STATUS_HALFTIME", Game.Intermission.halftime), ("STATUS_END_PERIOD", .endOfPeriod)])
    func mapsIntermissions(name: String, expected: Game.Intermission) throws {
        let json = """
        {"events":[{"id":"1","date":"2026-10-20T00:15Z","competitions":[{"status":{"displayClock":"0:00","period":2,
        "type":{"name":"\(name)","state":"in","shortDetail":"Halftime"}},"competitors":[
        {"homeAway":"home","score":"3","team":{"id":"1","abbreviation":"A","displayName":"A","shortDisplayName":"A"}},
        {"homeAway":"away","score":"7","team":{"id":"2","abbreviation":"B","displayName":"B","shortDisplayName":"B"}}]}]}]}
        """
        #expect(try ESPNProvider.parseScoreboard(Data(json.utf8), leagueID: "nfl").first?.intermission == expected)
    }
}

// MARK: - Storage

@Suite @MainActor struct NotificationStoreTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(sportsModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func unfollowingRemovesOverridesSoRefollowStartsFromDefaults() throws {
        let context = try makeContext()
        try context.follow(kc, leagueID: "nfl")
        try context.setPreference(.halftime, at: .team(chiefs), isEnabled: true)
        try context.setPreference(.halftime, at: .team(bills), isEnabled: true)
        try context.unfollow(chiefs)
        let left = try context.fetch(FetchDescriptor<NotificationPreference>())
        #expect(left.map(\.scopeID) == ["nfl/2"])
        #expect(try context.fetchCount(FetchDescriptor<FollowedTeam>()) == 0)
    }

    @Test func settingTwiceKeepsLatestValue() throws {
        let context = try makeContext()
        try context.setPreference(.final, at: .global, isEnabled: false)
        try context.setPreference(.final, at: .global, isEnabled: true)
        let rows = try context.fetch(FetchDescriptor<NotificationPreference>())
        #expect(rows.count == 1)
        #expect(rows.first?.isEnabled == true)
    }

    @Test func logSendsEachEventOnce() throws {
        let context = try makeContext()
        let event = GameEvent(type: .final, key: "final", headline: "Final", body: "")
        #expect(try context.markSent(event, gameID: "g1"))
        #expect(try !context.markSent(event, gameID: "g1"))
        #expect(try context.markSent(event, gameID: "g2"))
    }
}
