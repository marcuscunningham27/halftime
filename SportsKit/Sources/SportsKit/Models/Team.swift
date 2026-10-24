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

extension Team {
    /// The colour behind the team's pages: its alternate when the main one has no colour in it (Spurs' white),
    /// as long as the alternate is coloured or dark; otherwise the main colour.
    public var backdropHex: String? {
        guard let main = colorHex.flatMap(Self.rgb), main.saturation < 0.15,
              let alternate = alternateColorHex.flatMap(Self.rgb), alternate.saturation >= 0.15 || alternate.brightness < 0.4
        else { return colorHex }
        return alternateColorHex
    }

    private static func rgb(_ hex: String) -> (saturation: Double, brightness: Double)? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let parts = [value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF].map { Double($0) / 255 }
        let top = parts.max()!, bottom = parts.min()!
        return (top == 0 ? 0 : (top - bottom) / top, top)
    }
}
