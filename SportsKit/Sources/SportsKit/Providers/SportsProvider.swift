import Foundation

/// Every data source is normalised behind this protocol; UI never sees provider types.
public protocol SportsProvider: Sendable {
    func leagues() async throws -> [League]
    /// Games starting on `date`'s calendar day in the current time zone.
    func scoreboard(league: League, date: Date) async throws -> [Game]
    /// The league's most recent final scores, newest first; empty when nothing finished lately.
    func recentResults(league: League, before date: Date) async throws -> [Game]
    /// The team's live game, else its next one, else its most recent; nil if the schedule is empty.
    func featuredGame(for team: Follows.TeamRef) async throws -> Game?
    func standings(league: League) async throws -> Standings
    /// Per-play win (and, where offered, cover and over) chances; empty when the provider has none.
    func probabilities(for game: Game) async throws -> [ProbabilityPoint]
    /// Takes the game rather than an ID because providers need its league to build the request.
    /// Plays come back inside the detail; red zone uses the scoreboard's live situation, so no separate plays(id:) call.
    func gameDetail(for game: Game) async throws -> GameDetail
}
