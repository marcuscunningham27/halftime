import Foundation
import SwiftData

@Model
public final class FollowedLeague {
    #Unique<FollowedLeague>([\.leagueID])

    public var leagueID: String
    public var createdAt: Date

    public init(leagueID: League.ID, createdAt: Date = .now) {
        self.leagueID = leagueID
        self.createdAt = createdAt
    }
}

/// Stores enough of the team to draw the Following section without a network call.
@Model
public final class FollowedTeam {
    #Unique<FollowedTeam>([\.leagueID, \.teamID])

    public var teamID: String
    public var leagueID: String
    public var abbreviation: String
    public var displayName: String
    public var shortName: String
    public var colorHex: String?
    public var logoURL: URL?
    public var createdAt: Date
    /// Silences the team's alerts without unfollowing.
    public var isMuted: Bool = false

    public init(team: Team, leagueID: League.ID, createdAt: Date = .now) {
        teamID = team.id
        self.leagueID = leagueID
        abbreviation = team.abbreviation
        displayName = team.displayName
        shortName = team.shortName
        colorHex = team.colorHex
        logoURL = team.logoURL
        self.createdAt = createdAt
    }

    public var team: Team {
        Team(id: teamID, abbreviation: abbreviation, displayName: displayName, shortName: shortName,
             colorHex: colorHex, alternateColorHex: nil, logoURL: logoURL)
    }
}

/// What the user follows, as plain values for filtering games and choosing what to poll.
public struct Follows: Hashable, Sendable {
    public struct TeamRef: Hashable, Sendable {
        public let leagueID: League.ID
        public let teamID: Team.ID

        public init(leagueID: League.ID, teamID: Team.ID) {
            self.leagueID = leagueID
            self.teamID = teamID
        }
    }

    public let leagueIDs: Set<League.ID>
    public let teams: Set<TeamRef>

    public init(leagueIDs: Set<League.ID>, teams: Set<TeamRef>) {
        self.leagueIDs = leagueIDs
        self.teams = teams
    }

    public init(leagues: [FollowedLeague], teams: [FollowedTeam]) {
        self.init(leagueIDs: Set(leagues.map(\.leagueID)),
                  teams: Set(teams.map { TeamRef(leagueID: $0.leagueID, teamID: $0.teamID) }))
    }

    public var isEmpty: Bool { leagueIDs.isEmpty && teams.isEmpty }

    /// Followed leagues plus the leagues of followed teams.
    public var leagueIDsToPoll: Set<League.ID> {
        leagueIDs.union(teams.map(\.leagueID))
    }

    public func includes(_ game: Game) -> Bool {
        leagueIDs.contains(game.leagueID)
            || teams.contains(TeamRef(leagueID: game.leagueID, teamID: game.home.team.id))
            || teams.contains(TeamRef(leagueID: game.leagueID, teamID: game.away.team.id))
    }
}

/// Every model in the app's store.
public let sportsModels: [any PersistentModel.Type] = [
    FollowedTeam.self, FollowedLeague.self, NotificationPreference.self, NotificationLog.self,
]

/// One stored override; anything without a row falls back to the wider scope.
@Model
public final class NotificationPreference {
    #Unique<NotificationPreference>([\.scope, \.scopeID, \.eventType])

    public var scope: String
    public var scopeID: String
    public var eventType: String
    public var isEnabled: Bool

    public init(scope: PreferenceScope, event: NotificationEvent, isEnabled: Bool) {
        self.scope = scope.name
        scopeID = scope.id
        eventType = event.rawValue
        self.isEnabled = isEnabled
    }
}

/// Events already sent, so repeated polls and relaunches never notify twice.
@Model
public final class NotificationLog {
    #Unique<NotificationLog>([\.gameID, \.eventKey])

    public var gameID: String
    public var eventKey: String
    public var firedAt: Date

    public init(gameID: Game.ID, eventKey: String, firedAt: Date = .now) {
        self.gameID = gameID
        self.eventKey = eventKey
        self.firedAt = firedAt
    }
}

extension ModelContext {
    /// Inserting replaces any existing row for the same scope and event (#Unique).
    public func setPreference(_ event: NotificationEvent, at scope: PreferenceScope, isEnabled: Bool) throws {
        insert(NotificationPreference(scope: scope, event: event, isEnabled: isEnabled))
        try save()
    }

    public func resetPreferences(at scope: PreferenceScope) throws {
        let name = scope.name, id = scope.id
        try delete(model: NotificationPreference.self, where: #Predicate { $0.scope == name && $0.scopeID == id })
        try save()
    }

    public func follow(_ team: Team, leagueID: League.ID) throws {
        insert(FollowedTeam(team: team, leagueID: leagueID))
        try save()
    }

    /// Also drops the team's overrides, so re-following starts from the defaults.
    public func unfollow(_ team: Follows.TeamRef) throws {
        let leagueID = team.leagueID, teamID = team.teamID
        try delete(model: FollowedTeam.self, where: #Predicate { $0.leagueID == leagueID && $0.teamID == teamID })
        try resetPreferences(at: .team(team))
    }

    public func follow(leagueID: League.ID) throws {
        insert(FollowedLeague(leagueID: leagueID))
        try save()
    }

    public func unfollow(leagueID: League.ID) throws {
        try delete(model: FollowedLeague.self, where: #Predicate { $0.leagueID == leagueID })
        try resetPreferences(at: .league(leagueID))
    }

    /// Records the event and returns true, or returns false if it was already sent.
    public func markSent(_ event: GameEvent, gameID: Game.ID) throws -> Bool {
        let key = event.key
        let existing = try fetchCount(FetchDescriptor<NotificationLog>(predicate: #Predicate { $0.gameID == gameID && $0.eventKey == key }))
        guard existing == 0 else { return false }
        insert(NotificationLog(gameID: gameID, eventKey: key))
        try save()
        return true
    }

    /// Drops follows and overrides for leagues the app no longer carries (AFL and NRL), so they leave the sidebar.
    public func pruneRetiredLeagues() throws {
        let known = League.all.map(\.id)
        let teams = try fetch(FetchDescriptor<FollowedTeam>(predicate: #Predicate { !known.contains($0.leagueID) }))
        for team in teams { try unfollow(Follows.TeamRef(leagueID: team.leagueID, teamID: team.teamID)) }
        let leagues = try fetch(FetchDescriptor<FollowedLeague>(predicate: #Predicate { !known.contains($0.leagueID) }))
        for league in leagues { try unfollow(leagueID: league.leagueID) }
    }

    public func pruneNotificationLog(olderThan date: Date) throws {
        try delete(model: NotificationLog.self, where: #Predicate { $0.firedAt < date })
        try save()
    }
}
