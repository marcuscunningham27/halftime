import Foundation
import Testing
@testable import SportsKit

private let now = Date(timeIntervalSince1970: 1_792_459_200)

private func game(_ status: Game.Status, startsIn seconds: TimeInterval = 0) -> Game {
    let team = Team(id: "1", abbreviation: "AAA", displayName: "A", shortName: "A",
                    colorHex: nil, alternateColorHex: nil, logoURL: nil)
    let side = Game.Competitor(team: team, score: nil, periodScores: [])
    return Game(id: UUID().uuidString, leagueID: "nfl", startDate: now.addingTimeInterval(seconds), status: status,
                period: 0, clock: "", statusDetail: "", home: side, away: side)
}

@Suite struct PollingPolicyTests {
    @Test func liveGamePollsEvery15Seconds() {
        #expect(ScoreboardPoller.nextPoll(after: [game(.final), game(.live), game(.scheduled, startsIn: 3600)],
                                          failures: 0, now: now) == .seconds(15))
    }

    @Test func upcomingGamePollsEvery5Minutes() {
        #expect(ScoreboardPoller.nextPoll(after: [game(.scheduled, startsIn: 3600)], failures: 0, now: now) == .seconds(300))
    }

    @Test func wakesForKickoffSoonerThan5Minutes() {
        #expect(ScoreboardPoller.nextPoll(after: [game(.scheduled, startsIn: 120)], failures: 0, now: now) == .seconds(120))
    }

    @Test func delayedKickoffPollsEvery15Seconds() {
        #expect(ScoreboardPoller.nextPoll(after: [game(.scheduled, startsIn: -600)], failures: 0, now: now) == .seconds(15))
    }

    @Test func stopsWhenEverythingIsFinal() {
        #expect(ScoreboardPoller.nextPoll(after: [game(.final), game(.final)], failures: 0, now: now) == nil)
        #expect(ScoreboardPoller.nextPoll(after: [], failures: 0, now: now) == nil)
    }

    @Test(arguments: [(1, 15), (2, 30), (3, 60), (4, 120), (5, 120), (50, 120)])
    func backsOffExponentiallyCappedAt2Minutes(failures: Int, seconds: Int) {
        #expect(ScoreboardPoller.nextPoll(after: [game(.live)], failures: failures, now: now) == .seconds(seconds))
    }
}
