import Foundation

/// Game summaries and quick answers built straight from ESPN's numbers, with no model involved,
/// so they can't get a score, a player or a stat wrong.
public enum GameFacts {
    /// A few plain sentences: where a live game stands, or how a finished one was won.
    public static func summary(game: Game, detail: GameDetail) -> String {
        var sentences = [state(game)]
        if let leaders = topPerformers(game: game, detail: detail) { sentences.append(leaders) }
        if game.status == .live {
            let runs = scoringRuns(game: game, detail: detail)
            if [League.nba.id, League.wnba.id].contains(game.leagueID), let run = runs.last, run.points >= 6 {
                sentences.append("\(name(run.team, in: game)) are on a \(run.points)–0 run.")
            } else if let last = detail.plays.last(where: \.isScoring) {
                sentences.append("Latest score: \(last.text) (\(when(last, in: game))).")
            }
            if let situation = situation(game) { sentences.append(situation) }
        } else if let period = decidingPeriod(game) {
            sentences.append(period)
        }
        return sentences.joined(separator: " ")
    }

    /// The answer to a quick question from the stats, or nil when the stats can't answer it
    /// (the caller then asks the model).
    public static func answer(_ question: QuickQuestion, game: Game, detail: GameDetail) -> String? {
        switch question.kind {
        case .leaders(let categories): return leaders(categories, game: game, detail: detail)
        case .teamStats(let labels): return teamStats(labels, game: game, detail: detail)
        case .scoring: return scoring(game: game, detail: detail)
        case .biggestRun: return biggestRun(game: game, detail: detail)
        case .decidingPeriod: return decidingPeriod(game)
        case .scoringDrives: return scoringDrives(game: game, detail: detail)
        case .boxRows(let anchor, let columns, let firstOnly):
            return boxRows(anchor: anchor, columns: columns, firstOnly: firstOnly, game: game, detail: detail)
        case .plays(let types): return plays(types, game: game, detail: detail)
        case .model: return nil
        }
    }

    /// A typed question that names one of ESPN's leader categories ("who had the most points?", "top
    /// rebounder", "most passing yards") is answered from the leaders; anything else returns nil for the model.
    public static func answer(typed question: String, game: Game, detail: GameDetail) -> String? {
        if let player = player(question, game: game, detail: detail) { return player }
        let words = Set(question.lowercased().split { !$0.isLetter }.map { stem(String($0)) })
        // Match on every word of the category, so "Passing Yards" needs both and "Points" just "point".
        let matched = Set(detail.overview.leaders.map(\.category)).filter { category in
            let needed = category.lowercased().split { !$0.isLetter }.map { stem(String($0)) }
            return !needed.isEmpty && needed.allSatisfy(words.contains)
        }
        guard !matched.isEmpty else { return nil }
        return leaders(Array(matched), game: game, detail: detail)
    }

    /// Box score columns a question word asks for, across sports.
    static let columns: [String: [String]] = [
        "point": ["PTS"], "rebound": ["REB"], "board": ["REB"], "assist": ["AST", "A"], "steal": ["STL"], "block": ["BLK", "BS"],
        "three": ["3PT"], "minute": ["MIN", "TOI"], "turnover": ["TO"], "foul": ["PF"], "yard": ["YDS"], "touchdown": ["TD"],
        "catche": ["REC"], "reception": ["REC"], "carrie": ["CAR"], "interception": ["INT"], "sack": ["SACKS"], "tackle": ["TOT"],
        "goal": ["G"], "save": ["SV"], "shot": ["SOG"], "hit": ["H", "HT"], "hits": ["H", "HT"], "strikeout": ["K"],
        "rbi": ["RBI"], "rbis": ["RBI"], "homer": ["HR"],
    ]

    /// A question naming a player in the box score ("how many rebounds does Booker have?"): the stats it asks for,
    /// or the player's whole line when it names none. Matched on surname, so "Booker" finds Devin Booker.
    static func player(_ question: String, game: Game, detail: GameDetail) -> String? {
        let raw = question.lowercased().split { !$0.isLetter }.map(String.init)
        let words = Set(raw + raw.map(stem))
        let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv"]
        func surname(_ name: String) -> String? {
            name.lowercased().split { !$0.isLetter && $0 != "-" }.map(String.init).last { !suffixes.contains($0) }
        }
        let tables = detail.boxScores.filter { box in box.rows.contains { surname($0.name).map(words.contains) ?? false } }
        guard !tables.isEmpty else { return nil }
        let wanted: [String] = raw.contains("home") && words.contains("run") ? ["HR"]
            : words.flatMap { columns[$0] ?? [] }
        // One line per player found, each table's numbers labelled when the player is in several (passing, rushing…).
        var lines: [String: [String]] = [:]
        var order: [String] = []
        for box in tables {
            for row in box.rows where surname(row.name).map(words.contains) ?? false {
                let key = "\(row.name) (\(name(box.teamID, in: game)))"
                if lines[key] == nil { order.append(key); lines[key] = [] }
                let picked = box.labels.indices.filter { wanted.isEmpty || wanted.contains(box.labels[$0]) }
                    .filter { row.stats.indices.contains($0) }
                guard !picked.isEmpty else { continue }
                let stats = picked.map { "\(row.stats[$0]) \(box.labels[$0])" }.joined(separator: ", ")
                lines[key]?.append(tables.count > 1 ? "\(stats) (\(table(box)))" : stats)
            }
        }
        let found = order.compactMap { key in lines[key].flatMap { $0.isEmpty ? nil : "\(key): " + $0.joined(separator: "; ") + "." } }
        return found.isEmpty ? nil : found.joined(separator: "\n")
    }

    /// "passing", "goalies"… from ESPN's category, or batting / pitching for baseball's unnamed tables.
    static func table(_ box: BoxScore) -> String {
        if !box.category.hasPrefix("players") { return box.category }
        return box.labels.contains("IP") ? "pitching" : box.labels.contains("AB") ? "batting" : box.title
    }

    /// "points" → "point", "rebounder" → "rebound", "scorer" → "score": enough to match leader categories.
    static func stem(_ word: String) -> String {
        for suffix in ["ers", "er", "s"] where word.count > suffix.count + 3 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    // MARK: Sentences

    static func state(_ game: Game) -> String {
        let away = game.away, home = game.home
        let a = away.score ?? 0, h = home.score ?? 0
        let (lead, trail) = a >= h ? (away, home) : (home, away)
        let high = max(a, h), low = min(a, h)
        if game.status == .final {
            let overtime = game.statusDetail.contains("OT") || game.statusDetail.contains("SO") ? " in overtime" : ""
            return a == h ? "\(away.team.shortName) and \(home.team.shortName) drew \(a)–\(h)."
                : "\(lead.team.shortName) beat \(trail.team.shortName) \(high)–\(low)\(overtime)."
        }
        return a == h ? "\(away.team.shortName) and \(home.team.shortName) are tied at \(a) (\(game.statusDetail))."
            : "\(lead.team.shortName) lead \(trail.team.shortName) \(high)–\(low) (\(game.statusDetail))."
    }

    /// Each team's first listed leader, e.g. "Gilgeous-Alexander has 32 points for the Thunder".
    static func topPerformers(game: Game, detail: GameDetail) -> String? {
        let parts = [game.away.team, game.home.team].compactMap { team -> String? in
            detail.overview.leaders.first { $0.teamID == team.id }.map { "\($0.athlete) (\(team.shortName)) \(stat($0))" }
        }
        return parts.isEmpty ? nil : "Top performers: " + parts.joined(separator: "; ") + "."
    }

    /// NFL: who has the ball and where; baseball: count, outs and runners.
    static func situation(_ game: Game) -> String? {
        guard let situation = game.situation else { return nil }
        if let baseball = situation.baseball {
            let runners = [baseball.onFirst ? "first" : nil, baseball.onSecond ? "second" : nil, baseball.onThird ? "third" : nil]
                .compactMap { $0 }
            let bases = runners.isEmpty ? "bases empty" : "runners on " + runners.joined(separator: " and ")
            let outs = baseball.outs == 1 ? "1 out" : "\(baseball.outs) outs"
            return "\(outs), \(baseball.balls)-\(baseball.strikes) count, \(bases)."
        }
        guard let team = situation.possessionTeamID, let down = situation.downAndDistance else { return nil }
        return "\(name(team, in: game)) have the ball, \(down)\(situation.isRedZone ? " in the red zone" : "")."
    }

    /// The period the winner (or current leader) won by the most.
    static func decidingPeriod(_ game: Game) -> String? {
        let away = game.away.periodScores, home = game.home.periodScores
        guard away.count >= 2, away.count == home.count, let a = game.away.score, let h = game.home.score, a != h else { return nil }
        let leaderIsAway = a > h
        let margins = zip(away, home).map { leaderIsAway ? $0 - $1 : $1 - $0 }
        guard let best = margins.indices.max(by: { margins[$0] < margins[$1] }), margins[best] > 0 else { return nil }
        let team = leaderIsAway ? game.away.team.shortName : game.home.team.shortName
        let high = max(away[best], home[best]), low = min(away[best], home[best])
        return "\(team) did the most damage in \(game.league.periodTitle(best + 1)), winning it \(high)–\(low)."
    }

    // MARK: Quick answers

    static func leaders(_ categories: [String], game: Game, detail: GameDetail) -> String? {
        let wanted = detail.overview.leaders.filter { leader in
            categories.isEmpty || categories.contains { leader.category.localizedCaseInsensitiveContains($0) }
        }
        guard !wanted.isEmpty else { return nil }
        // One line per category, keeping ESPN's order: "Points: Gilgeous-Alexander (Thunder) 32, Castle (Spurs) 24."
        var order: [String] = []
        for leader in wanted where !order.contains(leader.category) { order.append(leader.category) }
        return order.map { category in
            // Highest first where the line starts with a number ("35", "264 YDS").
            let entries = wanted.filter { $0.category == category }
                .sorted { leadingNumber($0.line) > leadingNumber($1.line) }
                .map { "\($0.athlete) (\(name($0.teamID, in: game))) \($0.line)" }
            return "\(category): " + entries.joined(separator: ", ") + "."
        }.joined(separator: "\n")
    }

    static func teamStats(_ labels: [String], game: Game, detail: GameDetail) -> String? {
        var seen = Set<String>()
        let rows = labels.compactMap { label in
            detail.teamStats.first { $0.label.caseInsensitiveCompare(label) == .orderedSame && seen.insert($0.label).inserted }
        }
        guard !rows.isEmpty else { return nil }
        return rows.map { "\($0.label): \(game.away.team.shortName) \($0.away), \(game.home.team.shortName) \($0.home)." }
            .joined(separator: "\n")
    }

    static func scoring(game: Game, detail: GameDetail) -> String? {
        let scores = detail.plays.filter(\.isScoring)
        guard !scores.isEmpty else { return detail.plays.isEmpty ? nil : "No one has scored yet." }
        return scores.map { "\(when($0, in: game)) · \(name($0.teamID, in: game)): \($0.text)" }.joined(separator: "\n")
    }

    static func biggestRun(game: Game, detail: GameDetail) -> String? {
        guard let run = scoringRuns(game: game, detail: detail).max(by: { $0.points < $1.points }) else { return nil }
        return "\(name(run.team, in: game)) went on a \(run.points)–0 run in \(game.league.periodTitle(run.period))."
    }

    static func scoringDrives(game: Game, detail: GameDetail) -> String? {
        let drives = detail.drives.filter(\.isScore)
        guard !drives.isEmpty else { return nil }
        return drives.map { drive in
            let period = drive.plays.first.map { game.league.periodTitle($0.period) } ?? ""
            return "\(period) · \(name(drive.teamID, in: game)): \(drive.result ?? "Score") (\(drive.summary))"
        }.joined(separator: "\n")
    }

    /// Rows of the box score table whose labels include `anchor` (e.g. "IP" for pitchers, "SV" for goalies).
    static func boxRows(anchor: String, columns: [String], firstOnly: Bool, game: Game, detail: GameDetail) -> String? {
        let lines = [game.away.team, game.home.team].flatMap { team -> [String] in
            guard let box = detail.boxScores.first(where: { $0.teamID == team.id && $0.labels.contains(anchor) }) else { return [] }
            let rows = firstOnly ? Array(box.rows.prefix(1)) : box.rows
            return rows.map { row in
                let stats = columns.compactMap { column in
                    box.labels.firstIndex(of: column).flatMap { row.stats.indices.contains($0) ? "\(column) \(row.stats[$0])" : nil }
                }
                return "\(row.name) (\(team.shortName)): " + stats.joined(separator: ", ")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func plays(_ types: [String], game: Game, detail: GameDetail) -> String? {
        // Baseball repeats a hit on the pitch row ("Pitch 4 : Ball In Play"); keep the described result row.
        let found = detail.plays.filter { play in
            (types.contains(play.headline ?? "") || types.contains(play.type ?? "")) && !play.text.hasPrefix("Pitch")
        }
        guard !found.isEmpty else { return detail.plays.isEmpty ? nil : "None yet." }
        return found.map { "\(when($0, in: game)) · \(name($0.teamID, in: game)): \($0.text)" }.joined(separator: "\n")
    }

    // MARK: Helpers

    struct Run: Equatable {
        let team: Team.ID
        let points: Int
        let period: Int
    }

    /// Unanswered scoring streaks, oldest first, from the running score on each scoring play.
    static func scoringRuns(game: Game, detail: GameDetail) -> [Run] {
        var runs: [Run] = []
        var previous = (away: 0, home: 0)
        for play in detail.plays where play.isScoring {
            guard let a = play.awayScore, let h = play.homeScore else { continue }
            let (da, dh) = (a - previous.away, h - previous.home)
            previous = (a, h)
            let team: Team.ID
            let points: Int
            if da > 0, dh == 0 { (team, points) = (game.away.team.id, da) }
            else if dh > 0, da == 0 { (team, points) = (game.home.team.id, dh) }
            else { continue }
            if let last = runs.last, last.team == team {
                runs[runs.count - 1] = Run(team: team, points: last.points + points, period: last.period)
            } else {
                runs.append(Run(team: team, points: points, period: play.period))
            }
        }
        return runs
    }

    static func leadingNumber(_ line: String) -> Double {
        Double(line.prefix { $0.isNumber || $0 == "." }) ?? -1
    }

    static func name(_ id: Team.ID?, in game: Game) -> String {
        id == game.home.team.id ? game.home.team.shortName : id == game.away.team.id ? game.away.team.shortName : "—"
    }

    /// "Quarter 3, 4:12", or just the period where there's no clock (baseball).
    static func when(_ play: Play, in game: Game) -> String {
        let period = game.league.periodTitle(play.period)
        return play.clock.isEmpty ? period : "\(period), \(play.clock)"
    }

    /// "32 points" for a bare number, else the full line with its category: "21/29, 264 YDS, 1 TD (passing yards)".
    static func stat(_ leader: GameOverview.Leader) -> String {
        leader.line.allSatisfy(\.isNumber) ? "\(leader.line) \(leader.category.lowercased())"
            : "\(leader.line) (\(leader.category.lowercased()))"
    }
}

/// A one-click question on the game page, and how the stats answer it.
public struct QuickQuestion: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// ESPN's per-team leaders in categories containing these words (all categories when empty).
        case leaders([String])
        /// Team stat rows with these exact labels.
        case teamStats([String])
        /// Every scoring play.
        case scoring
        case biggestRun
        case decidingPeriod
        /// NFL drives that ended in points.
        case scoringDrives
        /// Box score rows from the table with an `anchor` column, showing `columns`.
        case boxRows(anchor: String, columns: [String], firstOnly: Bool)
        /// Plays of these types or headlines, e.g. home runs.
        case plays([String])
        /// Needs judgement: always goes to the model.
        case model
    }

    public let text: String
    public let kind: Kind
    public var id: String { text }

    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    /// Four questions that suit the sport's stats.
    public static func list(for leagueID: League.ID) -> [QuickQuestion] {
        switch leagueID {
        case League.nfl.id: [
            .init("Who had the most yards?", .leaders(["passing yards", "rushing yards", "receiving yards"])),
            .init("Who were the top passers?", .boxRows(anchor: "C/ATT", columns: ["C/ATT", "YDS", "TD", "INT"], firstOnly: false)),
            .init("How did turnovers change the game?", .teamStats(["Turnovers", "Fumbles lost", "Interceptions thrown"])),
            .init("What were the key scoring drives?", .scoringDrives),
        ]
        case League.nba.id, League.wnba.id: [
            .init("Who's the top scorer?", .leaders(["points"])),
            .init("How are the teams shooting from three?", .teamStats(["3PT", "Three Point %"])),
            .init("Who leads in rebounds and assists?", .leaders(["rebounds", "assists"])),
            .init("What was the biggest run?", .biggestRun),
        ]
        case League.mlb.id: [
            .init("Who drove in the runs?", .scoring),
            .init("How did the starting pitchers do?", .boxRows(anchor: "IP", columns: ["IP", "H", "ER", "BB", "K"], firstOnly: true)),
            .init("Who had the big hits?", .plays(["Home Run", "Triple", "Double"])),
            .init("Which inning decided it?", .decidingPeriod),
        ]
        case League.nhl.id: [
            .init("Who scored the goals?", .scoring),
            .init("How did the goalies play?", .boxRows(anchor: "SV", columns: ["SA", "SV", "GA", "SV%"], firstOnly: false)),
            .init("How did the power plays go?", .teamStats(["Power Play Goals", "Power Play Opportunities"])),
            .init("Which team controlled the shots?", .teamStats(["Shots", "Blocked Shots"])),
        ]
        case League.epl.id: [
            .init("Who scored and when?", .scoring),
            .init("Which team had more of the ball?", .teamStats(["Possession", "Passes"])),
            .init("Who were the standout players?", .model),
            .init("What were the big chances?", .teamStats(["SHOTS", "ON GOAL", "Corner Kicks"])),
        ]
        default: [
            .init("Who were the best players?", .leaders([])),
            .init("What were the turning points?", .model),
        ]
        }
    }
}
