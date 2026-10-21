/// League table, split into conferences or divisions, with the columns that matter for the sport.
public struct Standings: Hashable, Sendable {
    public struct Entry: Identifiable, Hashable, Sendable {
        public var id: Team.ID { team.id }
        public let team: Team
        /// Same order as `Standings.columns`; "–" where the provider has no value.
        public let values: [String]

        public init(team: Team, values: [String]) {
            self.team = team
            self.values = values
        }
    }

    public struct Group: Identifiable, Hashable, Sendable {
        public var id: String { name }
        public let name: String
        /// Best first.
        public let entries: [Entry]

        public init(name: String, entries: [Entry]) {
            self.name = name
            self.entries = entries
        }
    }

    /// Column headers, e.g. ["W", "L", "T", "PCT"].
    public let columns: [String]
    public let groups: [Group]

    public init(columns: [String], groups: [Group]) {
        self.columns = columns
        self.groups = groups
    }
}
