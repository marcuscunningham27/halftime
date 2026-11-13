import Foundation
import Testing
@testable import SportsKit

/// Today's scoreboard no longer lists a game that started before midnight; its own day's scoreboard still does.
private final class MidnightProvider: SportsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _lateGame: Game
    private var _todayIncludesLateGame = true
    var lateGame: Game { get { lock.withLock { _lateGame } } set { lock.withLock { _lateGame = newValue } } }
    var todayIncludesLateGame: Bool { get { lock.withLock { _todayIncludesLateGame } } set { lock.withLock { _todayIncludesLateGame = newValue } } }

    init(lateGame: Game) { _lateGame = lateGame }

    func scoreboard(league: League, date: Date) async throws -> [Game] {
        let today = date >= Calendar.current.startOfDay(for: .now)
        return today ? (todayIncludesLateGame ? [lateGame] : []) : [lateGame]
    }
    func leagues() async throws -> [League] { [.nba] }
    func recentResults(league: League, before date: Date) async throws -> [Game] { [] }
    func featuredGame(for team: Follows.TeamRef) async throws -> Game? { nil }
    func standings(league: League) async throws -> Standings { Standings(columns: [], groups: []) }
    func probabilities(for game: Game) async throws -> [ProbabilityPoint] { [] }
    func gameDetail(for game: Game) async throws -> GameDetail { GameDetail(plays: [], boxScores: [], teamStats: []) }
}

private func lateGame(_ status: Game.Status, home: Int) -> Game {
    let team = { (id: String) in
        Team(id: id, abbreviation: id, displayName: id, shortName: id, colorHex: nil, alternateColorHex: nil, logoURL: nil)
    }
    // Tipped off at 10 pm yesterday.
    let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(-2 * 3600)
    return Game(id: "late", leagueID: League.nba.id, startDate: start, status: status, period: 4, clock: "", statusDetail: "",
                home: .init(team: team("H"), score: home, periodScores: []), away: .init(team: team("A"), score: 99, periodScores: []))
}

@Suite @MainActor struct MidnightCarryTests {
    @Test func gameLiveAtMidnightStaysUntilItsFinalIsSeen() async {
        let provider = MidnightProvider(lateGame: lateGame(.live, home: 98))
        let poller = ScoreboardPoller(provider: provider, leagues: [.nba])
        var updates: [[Game]] = []
        poller.onUpdate = { _, new in updates.append(new) }

        await poller.refresh() // before midnight: today's list has it
        provider.todayIncludesLateGame = false // midnight passes
        provider.lateGame = lateGame(.final, home: 101)
        await poller.refresh()
        // Still there, now final, so the final alert can fire.
        #expect(updates.last?.map(\.status) == [.final])
        #expect(updates.last?.first?.home.score == 101)

        await poller.refresh()
        // Once seen final it belongs to yesterday again.
        #expect(updates.last?.isEmpty == true)
    }

    @Test func fixedDayIsNotCarried() async {
        // A page pinned to a date shows that date's games only, live or not.
        let provider = MidnightProvider(lateGame: lateGame(.live, home: 98))
        let poller = ScoreboardPoller(provider: provider, leagues: [.nba], date: .now)
        await poller.refresh()
        provider.todayIncludesLateGame = false
        await poller.refresh()
        #expect(poller.games.isEmpty)
    }
}
