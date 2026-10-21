import Foundation

/// The fantasy apps Sports can read a team from.
public enum FantasyProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case sleeper, espn, yahoo

    public var id: Self { self }

    public var title: String {
        switch self {
        case .sleeper: "Sleeper"
        case .espn: "ESPN Fantasy"
        case .yahoo: "Yahoo Fantasy"
        }
    }
}

/// A player as every provider describes them, tied to ESPN by `espnID` where known.
public struct FantasyPlayer: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let position: String?
    /// ESPN's abbreviation for the player's NFL team.
    public let team: String?
    public let espnID: String?
    /// ESPN's headshot, or the provider's own photo when there's no ESPN ID.
    public let photoURL: URL?
    /// The provider's injury designation; nil when healthy.
    public let injury: Injury?

    public struct Injury: Codable, Hashable, Sendable {
        /// "Questionable", "Doubtful", "Out", "IR"…
        public let status: String
        /// e.g. "Groin · Limited practice".
        public let detail: String?

        /// 0 healthy … 4 season-ending, for "most serious first".
        public var severity: Int {
            switch status.lowercased() {
            case "ir", "injury_reserve", "pup", "na", "sus", "suspension": 4
            case "out": 3
            case "doubtful": 2
            case "questionable": 1
            default: 0
            }
        }
    }

    public init(id: String, name: String, position: String?, team: String?, espnID: String?, photoURL: URL?, injury: Injury? = nil) {
        self.id = id
        self.name = name
        self.position = position
        self.team = team
        self.espnID = espnID
        self.photoURL = photoURL
        self.injury = injury
    }
}

/// Your team in one league: starting slots in order (nil where empty), then the bench.
public struct FantasyTeam: Sendable {
    public struct Slot: Sendable {
        public let label: String
        public let player: FantasyPlayer?
    }

    public let lineup: [Slot]
    public let bench: [FantasyPlayer]

    public var players: [FantasyPlayer] { lineup.compactMap(\.player) + bench }
    public var starters: Set<String> { Set(lineup.compactMap { $0.player?.id }) }
}

/// This week's head-to-head: each side's team, manager, live points and projected total.
public struct FantasyMatchup: Sendable {
    public struct Side: Sendable {
        public let teamName: String
        public let manager: String?
        public let avatarURL: URL?
        public let points: Double
        public let projected: Double
    }

    public let me: Side
    /// nil on a bye week.
    public let opponent: Side?

    /// Your chance of winning, estimated from the two projected totals: the gap measured against a typical
    /// spread of weekly scores (a normal curve). Close to what Sleeper shows; nil on a bye.
    /// shortcut: uses full-week projections even mid-week; blend in live points if it should track games in progress.
    public var winProbability: Double? {
        guard let opponent else { return nil }
        let spread = 45.0 // standard deviation of the score difference, in points
        let z = (me.projected - opponent.projected) / spread
        return 0.5 * (1 + erf(z / 2.0.squareRoot()))
    }
}

/// A league saved in Settings: which app, which league, and which team in it is yours.
public struct FantasyLeagueRef: Codable, Hashable, Identifiable, Sendable {
    public let provider: FantasyProvider
    public let leagueID: String
    public let name: String
    /// Sleeper: your user ID. ESPN: your team's ID in the league.
    public let memberID: String

    public var id: String { "\(provider.rawValue):\(leagueID)" }

    public init(provider: FantasyProvider, leagueID: String, name: String, memberID: String) {
        self.provider = provider
        self.leagueID = leagueID
        self.name = name
        self.memberID = memberID
    }
}

public enum FantasyData {
    public enum FantasyError: LocalizedError {
        case unsupported(FantasyProvider)
        case notOnTeam

        public var errorDescription: String? {
            switch self {
            case .unsupported(let provider): "\(provider.title) isn’t supported yet."
            case .notOnTeam: "You don’t have a team in this league."
            }
        }
    }

    /// Your current team in a saved league.
    public static func team(for league: FantasyLeagueRef, season: String, espnCredentials: ESPNFantasy.Credentials?,
                            playersCache: URL) async throws -> FantasyTeam {
        let team: FantasyTeam?
        switch league.provider {
        case .sleeper:
            team = try await Sleeper.team(leagueID: league.leagueID, userID: league.memberID, playersCache: playersCache)
        case .espn:
            team = try await ESPNFantasy.team(leagueID: league.leagueID, season: season, teamID: league.memberID,
                                              credentials: espnCredentials)
        case .yahoo:
            throw FantasyError.unsupported(.yahoo)
        }
        guard let team else { throw FantasyError.notOnTeam }
        return team
    }

    /// Projected points per `FantasyPlayer.id` for one week, in the league's scoring.
    public static func projections(for league: FantasyLeagueRef, week: Int, season: String,
                                   espnCredentials: ESPNFantasy.Credentials?) async throws -> [String: Double] {
        switch league.provider {
        case .sleeper: try await Sleeper.projections(leagueID: league.leagueID, season: season, week: week)
        case .espn: try await ESPNFantasy.projections(leagueID: league.leagueID, season: season, week: week, credentials: espnCredentials)
        case .yahoo: throw FantasyError.unsupported(.yahoo)
        }
    }

    /// Your matchup for one week; `projections` (from `projections(for:)`) sets the projected totals.
    public static func matchup(for league: FantasyLeagueRef, week: Int, season: String, projections: [String: Double],
                               espnCredentials: ESPNFantasy.Credentials?) async throws -> FantasyMatchup? {
        switch league.provider {
        case .sleeper: try await Sleeper.matchup(leagueID: league.leagueID, userID: league.memberID, week: week, projections: projections)
        case .espn: try await ESPNFantasy.matchup(leagueID: league.leagueID, season: season, teamID: league.memberID, week: week,
                                                  projections: projections, credentials: espnCredentials)
        case .yahoo: throw FantasyError.unsupported(.yahoo)
        }
    }

    /// Fantasy points per `FantasyPlayer.id` for one week.
    public static func points(for league: FantasyLeagueRef, week: Int, season: String,
                              espnCredentials: ESPNFantasy.Credentials?) async throws -> [String: Double] {
        switch league.provider {
        case .sleeper: try await Sleeper.points(leagueID: league.leagueID, week: week)
        case .espn: try await ESPNFantasy.points(leagueID: league.leagueID, season: season, week: week, credentials: espnCredentials)
        case .yahoo: throw FantasyError.unsupported(.yahoo)
        }
    }
}
