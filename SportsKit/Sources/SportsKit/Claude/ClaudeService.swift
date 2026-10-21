import Foundation

/// The one place the app talks to the Anthropic API. Prompts are always grounded in SportsKit's
/// structured game data, and the model is told not to go beyond it.
public struct ClaudeService: Sendable {
    public enum ClaudeError: LocalizedError {
        case http(Int, String)
        case empty
        case cutOff
        case refused

        public var errorDescription: String? {
            switch self {
            case .http(401, _): "Your Anthropic API key was rejected. Check it in Settings › Summaries."
            case .http(let code, let message): "Claude couldn’t answer (\(code)). \(message)"
            case .empty: "Claude returned an empty answer."
            case .cutOff: "Claude ran out of room before answering. Try again."
            case .refused: "Claude declined to answer this one."
            }
        }
    }

    /// Small and fast, as recaps are short and frequent.
    public static let model = "claude-haiku-5-5"

    let apiKey: String
    let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// A short recap of a finished game, or a catch-up on a live one.
    public func recap(game: Game, detail: GameDetail) async throws -> String {
        try await complete(system: GamePrompt.system(for: game), user: GamePrompt.recap(game: game, detail: detail))
    }

    /// Haiku 5.5 thinks by default and its thinking counts against max_tokens, so the cap leaves room for
    /// thinking plus a short answer, and effort is low: these are short, plain-text tasks.
    public func complete(system: String, user: String, maxTokens: Int = 4000) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "max_tokens": maxTokens,
            "output_config": ["effort": "low"],
            "system": system,
            "messages": [["role": "user", "content": user]],
        ] as [String: Any])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeError.http(http.statusCode, Self.errorMessage(data) ?? "")
        }
        return try Self.parse(data)
    }

    /// The text blocks of a Messages API response, joined; thinking blocks are skipped.
    static func parse(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if response.stop_reason == "refusal" { throw ClaudeError.refused }
        let text = response.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw response.stop_reason == "max_tokens" ? ClaudeError.cutOff : ClaudeError.empty }
        return text
    }

    static func errorMessage(_ data: Data) -> String? {
        struct Response: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
        return try? JSONDecoder().decode(Response.self, from: data).error.message
    }
}

/// Turns a game into plain text for a prompt: only facts from the provider, nothing derived by the model.
public enum GamePrompt {
    public static let recapSystem = """
    You write short sports recaps for a scores app. Use only the game data you are given: never invent \
    stats, players, quotes or plays that are not in it. Write two short paragraphs, 80 to 120 words in all, \
    in plain prose with no headings, lists or markdown. Lead with the result (or the state of play if the game \
    is still going), then the moments and players that decided it. Use team names as given.
    """

    static let catchUpSystem = """
    You catch up a fan who has just tuned in to a live game, for a scores app. Use only the game data you are \
    given: never invent stats, players, quotes or plays that are not in it. Write two or three sentences on \
    what has happened so far and the current state of play, then one sentence starting "Watch for" on what \
    matters next, based only on the score, time left and situation given. Plain prose, no markdown, under 90 words.
    """

    public static let playLineSystem = """
    You turn a raw play-by-play entry into one short, lively sentence for a phone notification, the way a \
    commentator would say it, under 15 words. Use surnames only and drop notes like (Shotgun), snapper and holder. \
    Use only the players and facts in the entry. No score, no emoji, no quotation marks. \
    Example: (Shotgun) A.Smith pass short right to B.Jones for 9 yards, TOUCHDOWN. becomes: Smith finds Jones for a 9-yard touchdown.
    """

    /// The scoring play that produced the game's score, once the play-by-play has caught up with it;
    /// found by score rather than position, as later baskets may already be in the feed.
    public static func latestScoringPlay(in detail: GameDetail, matching game: Game) -> Play? {
        detail.plays.last { $0.isScoring && $0.awayScore == game.away.score && $0.homeScore == game.home.score }
    }

    public static func playLine(game: Game, play: Play) -> String {
        let team = play.teamID == game.home.team.id ? game.home.team.shortName
            : play.teamID == game.away.team.id ? game.away.team.shortName : "Unknown team"
        return """
        \(game.league.name): \(game.away.team.displayName) at \(game.home.team.displayName)
        Scoring team: \(team)
        Play (period \(play.period), \(play.clock)): \(play.text)
        """
    }

    public static let askSystem = """
    You answer a fan's question about one game for a scores app. Use only the game data you are given. \
    If the data doesn't answer the question, say you don't have that information; never guess or invent \
    stats, players or plays. Answer in one to three short sentences of plain prose, no markdown.
    """

    /// The recap data plus the top rows of each box score, then the question.
    public static func ask(_ question: String, game: Game, detail: GameDetail) -> String {
        var lines = [recap(game: game, detail: detail)]
        if !detail.boxScores.isEmpty {
            lines.append("\nBox score (top 3 per category):")
            for box in detail.boxScores {
                lines.append("\(box.title) [\(box.labels.joined(separator: ", "))]")
                // shortcut: top 3 rows keeps the on-device model inside its small context; send all rows if answers miss bench players.
                lines += box.rows.prefix(3).map { "- \($0.name): \($0.stats.joined(separator: ", "))" }
            }
        }
        lines.append("\nQuestion: \(question)")
        return lines.joined(separator: "\n")
    }

    /// Catch-up instructions while the game is live, recap instructions otherwise.
    public static func system(for game: Game) -> String {
        game.status == .live ? catchUpSystem : recapSystem
    }

    public static func recap(game: Game, detail: GameDetail) -> String {
        let away = game.away, home = game.home
        func name(_ id: Team.ID?) -> String {
            id == home.team.id ? home.team.shortName : id == away.team.id ? away.team.shortName : ""
        }
        var lines = [
            "\(game.league.name): \(away.team.displayName) at \(home.team.displayName)",
            "Status: \(game.status == .final ? "Final" : game.status == .live ? "In progress" : "Not started") (\(game.statusDetail))",
            "Score: \(away.team.shortName) \(away.score ?? 0), \(home.team.shortName) \(home.score ?? 0)",
        ]
        if !away.periodScores.isEmpty {
            lines.append("By period: \(away.team.shortName) \(away.periodScores.map(String.init).joined(separator: " ")); "
                + "\(home.team.shortName) \(home.periodScores.map(String.init).joined(separator: " "))")
            // Running totals spelled out, so a small model never has to add up who led when.
            var a = 0, h = 0
            for (i, (ap, hp)) in zip(away.periodScores, home.periodScores).enumerated() {
                a += ap; h += hp
                let state = a == h ? "tied" : "\(a > h ? away.team.shortName : home.team.shortName) leading"
                lines.append("After period \(i + 1): \(away.team.shortName) \(a), \(home.team.shortName) \(h) (\(state))")
            }
        }
        if game.status == .live {
            var now = "Now: period \(game.period), \(game.clock) left"
            if let situation = game.situation {
                if let team = situation.possessionTeamID { now += "; \(name(team)) have the ball" }
                if let down = situation.downAndDistance { now += ", \(down)" }
                if situation.isRedZone { now += " (red zone)" }
            }
            lines.append(now)
        }
        let records = [away, home].compactMap { c in c.record.map { "\(c.team.shortName) \($0)" } }
        if !records.isEmpty { lines.append("Records: " + records.joined(separator: ", ")) }

        let scoring = detail.plays.filter(\.isScoring)
        if !scoring.isEmpty {
            lines.append("\nScoring plays:")
            lines += scoring.map { play in
                let score = play.awayScore.flatMap { a in play.homeScore.map { " [\(a)–\($0)]" } } ?? ""
                return "- P\(play.period) \(play.clock) \(name(play.teamID)): \(play.text)\(score)"
            }
        }
        if game.status == .live, let last = detail.plays.suffix(8).nilIfEmpty {
            lines.append("\nLatest plays:")
            lines += last.map { "- P\($0.period) \($0.clock): \($0.text)" }
        }
        if !detail.overview.leaders.isEmpty {
            lines.append("\nLeaders:")
            lines += detail.overview.leaders.map { "- \($0.category), \(name($0.teamID)): \($0.athlete) \($0.line)" }
        }
        if !detail.teamStats.isEmpty {
            lines.append("\nTeam stats (\(away.team.shortName) / \(home.team.shortName)):")
            lines += detail.teamStats.map { "- \($0.label): \($0.away) / \($0.home)" }
        }
        return lines.joined(separator: "\n")
    }
}

private extension Collection {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
