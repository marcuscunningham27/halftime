import Foundation

/// The followed teams, mirrored into the App Group so the widget can offer them without opening the app's store.
public struct WidgetTeam: Codable, Hashable, Sendable, Identifiable {
    public let leagueID: League.ID
    public let teamID: Team.ID
    public let name: String

    public var id: String { "\(leagueID)/\(teamID)" }
    public var ref: Follows.TeamRef { Follows.TeamRef(leagueID: leagueID, teamID: teamID) }

    public init(leagueID: League.ID, teamID: Team.ID, name: String) {
        self.leagueID = leagueID
        self.teamID = teamID
        self.name = name
    }

    /// Team-prefixed, so macOS allows it for a signed app without a registered group.
    public static let appGroup = "9C872WSWWS.com.marcuscunningham.SportsApp"
    private static let key = "followedTeams"
    private static let leaguesKey = "followedLeagues"

    public static func save(_ teams: [WidgetTeam]) {
        UserDefaults(suiteName: appGroup)?.set(try? JSONEncoder().encode(teams), forKey: key)
    }

    /// Followed leagues, so the widget can fill spare rows with their games.
    public static func saveLeagues(_ ids: [League.ID]) {
        UserDefaults(suiteName: appGroup)?.set(ids, forKey: leaguesKey)
    }

    public static func loadLeagues() -> [League.ID] {
        UserDefaults(suiteName: appGroup)?.stringArray(forKey: leaguesKey) ?? []
    }

    public static func load() -> [WidgetTeam] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WidgetTeam].self, from: data)) ?? []
    }
}
