import Foundation

public struct Team: Identifiable, Hashable, Sendable {
    /// Unique within a league only; pair with a league ID when storing.
    public let id: String
    public let abbreviation: String
    /// Full name, e.g. "San Francisco 49ers".
    public let displayName: String
    /// Nickname, e.g. "49ers".
    public let shortName: String
    /// Hex RGB without "#", e.g. "aa0000".
    public let colorHex: String?
    public let alternateColorHex: String?
    public let logoURL: URL?

    public init(id: String, abbreviation: String, displayName: String, shortName: String,
                colorHex: String?, alternateColorHex: String?, logoURL: URL?) {
        self.id = id
        self.abbreviation = abbreviation
        self.displayName = displayName
        self.shortName = shortName
        self.colorHex = colorHex
        self.alternateColorHex = alternateColorHex
        self.logoURL = logoURL
    }
}
