import Foundation

/// Where a preference lives. Team overrides league, which overrides global, which overrides the event default.
public enum PreferenceScope: Hashable, Sendable {
    case global
    case league(League.ID)
    case team(Follows.TeamRef)

    public var name: String {
        switch self {
        case .global: "global"
        case .league: "league"
        case .team: "team"
        }
    }

    public var id: String {
        switch self {
        case .global: ""
        case .league(let leagueID): leagueID
        case .team(let ref): "\(ref.leagueID)/\(ref.teamID)"
        }
    }
}

/// Decides whether an event should notify, as a pure function of follows and stored preferences.
public struct NotificationRules: Sendable {
    private struct Key: Hashable {
        let scope: String, scopeID: String, event: String
    }

    public let follows: Follows
    private let mutedTeams: Set<Follows.TeamRef>
    private let overrides: [Key: Bool]

    public init(follows: Follows, mutedTeams: Set<Follows.TeamRef>,
                overrides: [(scope: PreferenceScope, event: NotificationEvent, isEnabled: Bool)]) {
        self.init(follows: follows, mutedTeams: mutedTeams, keyed: overrides.map {
            (Key(scope: $0.scope.name, scopeID: $0.scope.id, event: $0.event.rawValue), $0.isEnabled)
        })
    }

    public init(leagues: [FollowedLeague], teams: [FollowedTeam], preferences: [NotificationPreference]) {
        self.init(follows: Follows(leagues: leagues, teams: teams),
                  mutedTeams: Set(teams.filter(\.isMuted).map { Follows.TeamRef(leagueID: $0.leagueID, teamID: $0.teamID) }),
                  keyed: preferences.map { (Key(scope: $0.scope, scopeID: $0.scopeID, event: $0.eventType), $0.isEnabled) })
    }

    private init(follows: Follows, mutedTeams: Set<Follows.TeamRef>, keyed: [(Key, Bool)]) {
        self.follows = follows
        self.mutedTeams = mutedTeams
        overrides = Dictionary(keyed, uniquingKeysWith: { $1 })
    }

    /// The effective setting at a scope, falling back through the wider scopes to the default.
    public func resolved(_ event: NotificationEvent, at scope: PreferenceScope) -> Bool {
        func value(_ scope: PreferenceScope) -> Bool? {
            overrides[Key(scope: scope.name, scopeID: scope.id, event: event.rawValue)]
        }
        switch scope {
        case .global:
            return value(.global) ?? event.isOnByDefault
        case .league:
            return value(scope) ?? resolved(event, at: .global)
        case .team(let ref):
            return value(scope) ?? resolved(event, at: .league(ref.leagueID))
        }
    }

    public func isMuted(_ team: Follows.TeamRef) -> Bool {
        mutedTeams.contains(team)
    }

    /// Followed teams in the game decide (any unmuted one that wants it); otherwise a followed league does.
    public func shouldNotify(_ event: NotificationEvent, for game: Game) -> Bool {
        guard event.applies(to: game.league) else { return false }
        let teams = [game.home.team.id, game.away.team.id]
            .map { Follows.TeamRef(leagueID: game.leagueID, teamID: $0) }
            .filter(follows.teams.contains)
        if !teams.isEmpty {
            return teams.contains { !mutedTeams.contains($0) && resolved(event, at: .team($0)) }
        }
        return follows.leagueIDs.contains(game.leagueID) && resolved(event, at: .league(game.leagueID))
    }
}

/// Quiet hours hold alerts until they end. Times are minutes after midnight; a window may cross midnight.
public struct QuietHours: Sendable {
    public let isEnabled: Bool
    public let start: Int
    public let end: Int

    public init(isEnabled: Bool, start: Int, end: Int) {
        self.isEnabled = isEnabled
        self.start = start
        self.end = end
    }

    /// When a held alert should go out, or nil to send it now.
    public func holdUntil(_ now: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled, start != end else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let minute = c.hour! * 60 + c.minute!
        let isQuiet = start < end ? (start <= minute && minute < end) : (minute >= start || minute < end)
        guard isQuiet else { return nil }
        return calendar.nextDate(after: now, matching: DateComponents(hour: end / 60, minute: end % 60),
                                 matchingPolicy: .nextTime)
    }
}
