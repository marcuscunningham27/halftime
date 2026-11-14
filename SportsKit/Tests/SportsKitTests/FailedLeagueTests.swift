import Foundation
import Testing
@testable import SportsKit

/// NBA's scoreboard can be made to fail; NHL's always answers.
private final class FlakyProvider: SportsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _nbaFails = false
    private var _homeScore = 0
    var nbaFails: Bool { get { lock.withLock { _nbaFails } } set { lock.withLock { _nbaFails = newValue } } }
    var homeScore: Int { get { lock.withLock { _homeScore } } set { lock.withLock { _homeScore = newValue } } }

    func scoreboard(league: League, date: Date) async throws -> [Game] {
        if league.id == League.nba.id {
            if nbaFails { throw URLError(.timedOut) }
            return [game("nba-game", .nba, home: homeScore)]
        }
        return [game("nhl-game", .nhl, home: 0)]
    }
    func leagues() async throws -> [League] { [.nba, .nhl] }
    func recentResults(league: League, before date: Date) async throws -> [Game] { [] }
    func featuredGame(for team: Follows.TeamRef) async throws -> Game? { nil }
    func standings(league: League) async throws -> Standings { Standings(columns: [], groups: []) }
    func probabilities(for game: Game) async throws -> [ProbabilityPoint] { [] }
    func gameDetail(for game: Game) async throws -> GameDetail { GameDetail(plays: [], boxScores: [], teamStats: []) }
}

private func game(_ id: String, _ league: League, home: Int) -> Game {
    let team = { (id: String) in
        Team(id: id, abbreviation: id, displayName: id, shortName: id, colorHex: nil, alternateColorHex: nil, logoURL: nil)
    }
    return Game(id: id, leagueID: league.id, startDate: .now, status: .live, period: 2, clock: "", statusDetail: "",
                home: .init(team: team("H"), score: home, periodScores: []), away: .init(team: team("A"), score: 0, periodScores: []))
}

@Suite @MainActor struct FailedLeagueTests {
    @Test func failedLeagueKeepsItsGamesSoTheNextChangeIsCompared() async {
        let provider = FlakyProvider()
        let poller = ScoreboardPoller(provider: provider, leagues: [.nba, .nhl])
        var updates: [(old: [Game], new: [Game])] = []
        poller.onUpdate = { updates.append(($0, $1)) }

        await poller.refresh()
        provider.nbaFails = true
        await poller.refresh()
        // The NBA game is still listed with its last score while its league is down.
        #expect(updates.last?.new.first { $0.id == "nba-game" }?.home.score == 0)

        provider.nbaFails = false
        provider.homeScore = 3
        await poller.refresh()
        // So the next good poll compares 0 against 3, and the score alert can fire.
        #expect(updates.last?.old.first { $0.id == "nba-game" }?.home.score == 0)
        #expect(updates.last?.new.first { $0.id == "nba-game" }?.home.score == 3)
    }
}
