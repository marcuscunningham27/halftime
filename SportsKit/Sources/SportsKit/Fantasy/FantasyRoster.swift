/// Your fantasy players across every saved league, for spotting them in a live game.
public struct FantasyRoster: Hashable, Sendable {
    public let players: [FantasyPlayer]

    public init(players: [FantasyPlayer]) {
        self.players = players
    }

    /// ESPN's NFL play-by-play short form: "Jayden Daniels" → "J.Daniels", "Amon-Ra St. Brown" → "A.St. Brown".
    static func shortName(_ name: String) -> String? {
        let suffixes: Set<String> = ["jr.", "jr", "sr.", "sr", "ii", "iii", "iv", "v"]
        let words = name.split(separator: " ").filter { !suffixes.contains($0.lowercased()) }
        guard words.count >= 2, let initial = words[0].first else { return nil }
        return "\(initial).\(words.dropFirst().joined(separator: " "))"
    }

    /// The players a play's text names, by full or short name, as whole words.
    public func players(in text: String) -> [FantasyPlayer] {
        players.filter { player in
            [player.name, Self.shortName(player.name)].compactMap { $0 }.contains { Self.text(text, names: $0) }
        }
    }

    /// Whether a box score row is one of yours: by ESPN ID, else by name.
    public func contains(athleteID: String, name: String) -> Bool {
        players.contains { $0.espnID == athleteID || $0.name == name }
    }

    /// `name` appears in `text` not glued to other letters ("J.Brown" isn't in "AJ.Brown" or "J.Browning").
    private static func text(_ text: String, names name: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: name, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false) && before != "." && !(after?.isLetter ?? false) { return true }
            searchStart = range.upperBound
        }
        return false
    }
}
