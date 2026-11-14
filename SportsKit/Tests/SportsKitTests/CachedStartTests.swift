import Foundation
import Testing
@testable import SportsKit

/// Serves last launch's games from "disk" and newer ones from "the network".
private struct CachingProvider: SportsProvider {
    let cached: [Game]
    let fresh: [Game]

    func cachedScoreboard(league: League, date: Date) async -> [Game] { cached }
    func scoreboard(league: League, date: Date) async throws -> [Game] { fresh }
    func leagues() async throws -> [League] { [.nba] }
    func recentResults(league: League, before date: Date) async throws -> [Game] { [] }
    func featuredGame(for team: Follows.TeamRef) async throws -> Game? { nil }
    func standings(league: League) async throws -> Standings { Standings(columns: [], groups: []) }
    func probabilities(for game: Game) async throws -> [ProbabilityPoint] { [] }
    func gameDetail(for game: Game) async throws -> GameDetail { GameDetail(plays: [], boxScores: [], teamStats: []) }
}

/** Like CachingProvider, but NBA's first fetch fails while NHL's answers. */
private final class FirstFetchFailsProvider: SportsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var nbaCalls = 0
    let cached: [Game]
    let fresh: [Game]
    init(cached: [Game], fresh: [Game]) { self.cached = cached; self.fresh = fresh }

    func cachedScoreboard(league: League, date: Date) async -> [Game] { league.id == League.nba.id ? cached : [] }
    func scoreboard(league: League, date: Date) async throws -> [Game] {
        guard league.id == League.nba.id else { return [] }
        let first = lock.withLock { nbaCalls += 1; return nbaCalls == 1 }
        if first { throw URLError(.timedOut) }
        return fresh
    }
    func leagues() async throws -> [League] { [.nba, .nhl] }
    func recentResults(league: League, before date: Date) async throws -> [Game] { [] }
    func featuredGame(for team: Follows.TeamRef) async throws -> Game? { nil }
    func standings(league: League) async throws -> Standings { Standings(columns: [], groups: []) }
    func probabilities(for game: Game) async throws -> [ProbabilityPoint] { [] }
    func gameDetail(for game: Game) async throws -> GameDetail { GameDetail(plays: [], boxScores: [], teamStats: []) }
}

private func game(_ status: Game.Status, home: Int, away: Int) -> Game {
    let team = { (id: String) in
        Team(id: id, abbreviation: id, displayName: id, shortName: id, colorHex: nil, alternateColorHex: nil, logoURL: nil)
    }
    return Game(id: "1", leagueID: League.nba.id, startDate: .now, status: status, period: 4, clock: "", statusDetail: "",
                home: .init(team: team("H"), score: home, periodScores: []), away: .init(team: team("A"), score: away, periodScores: []))
}

@Suite @MainActor struct CachedStartTests {
    @Test func showsLastLaunchsScoresBeforeTheFirstFetch() async {
        let poller = ScoreboardPoller(provider: CachingProvider(cached: [game(.live, home: 80, away: 75)], fresh: []),
                                      leagues: [.nba], date: .now)
        await poller.seedFromCache()
        #expect(poller.games.map(\.home.score) == [80])
    }

    @Test func firstFetchAfterACachedStartIsNotAChange() async {
        // The game went final while the app was closed: that mustn't read as a change and alert.
        let poller = ScoreboardPoller(provider: CachingProvider(cached: [game(.live, home: 80, away: 75)],
                                                                fresh: [game(.final, home: 101, away: 99)]),
                                      leagues: [.nba], date: .now)
        var olds: [[Game]] = []
        poller.onUpdate = { old, _ in olds.append(old) }
        await poller.seedFromCache()
        await poller.refresh()
        #expect(olds == [[]])
        #expect(poller.games.map(\.home.score) == [101])
        // Later fetches compare as usual.
        await poller.refresh()
        #expect(olds.last?.map(\.home.score) == [101])
    }

    @Test func cachedGamesAreNotKeptForALeagueWhoseFirstFetchFails() async {
        // Last launch's copy must not stand in as real data, or its next fetch would alert on everything since.
        let poller = ScoreboardPoller(provider: FirstFetchFailsProvider(cached: [game(.live, home: 80, away: 75)],
                                                                        fresh: [game(.final, home: 101, away: 99)]),
                                      leagues: [.nba, .nhl], date: .now)
        var olds: [[Game]] = []
        poller.onUpdate = { old, _ in olds.append(old) }
        await poller.seedFromCache()
        await poller.refresh() // NBA fails, NHL answers
        await poller.refresh() // NBA answers
        #expect(olds.last?.isEmpty == true)
        #expect(poller.games.map(\.home.score) == [101])
    }
}
