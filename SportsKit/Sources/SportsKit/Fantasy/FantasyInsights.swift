import Foundation

/// One week of your starters: who started, what they scored, and what they were projected.
public struct FantasyWeekResult: Sendable {
    public struct Starter: Sendable {
        public let playerID: String
        public let name: String
        public let position: String?
        public let actual: Double
        public let projected: Double
    }

    public let week: Int
    public let starters: [Starter]

    public var actual: Double { starters.reduce(0) { $0 + $1.actual } }
    public var projected: Double { starters.reduce(0) { $0 + $1.projected } }
}

public struct FantasyStanding: Identifiable, Sendable {
    public let id: String
    public let teamName: String
    public let wins: Int
    public let losses: Int
    public let ties: Int
    public let pointsFor: Double
    public let isMine: Bool

    public var record: String { ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)" }

    /// By record, then points for, as fantasy apps rank.
    public static func ranked(_ standings: [FantasyStanding]) -> [FantasyStanding] {
        standings.sorted { ($0.wins, Double($0.ties) / 2, $0.pointsFor) > ($1.wins, Double($1.ties) / 2, $1.pointsFor) }
    }
}

/// The league's calendar: when playoffs start and the trade deadline, as NFL weeks.
public struct FantasyCalendar: Sendable {
    public let playoffWeekStart: Int
    public let tradeDeadlineWeek: Int?
}

/// A news item on a player, from ESPN's fantasy feed (Rotowire blurbs and analysis).
public struct PlayerNews: Identifiable, Hashable, Sendable {
    public let id: String
    public let headline: String
    public let story: String?
    public let published: Date
    public let source: String
    /// The story on espn.com (or ESPN's mobile page for Rotowire blurbs).
    public let url: URL?
}

/// Season numbers from weekly results: actual against projected per week, by position and by starter.
public struct SeasonTrend: Sendable {
    public let weeks: [FantasyWeekResult]
    public let actualPerWeek: Double
    public let projectedPerWeek: Double
    /// Average actual minus projected per start, best last.
    public let gapByPosition: [(position: String, gap: Double)]
    /// Total actual minus projected across all starts, worst first.
    public let gapByStarter: [(name: String, gap: Double)]

    public var gapPerWeek: Double { actualPerWeek - projectedPerWeek }

    public init(weeks: [FantasyWeekResult]) {
        self.weeks = weeks
        let count = Double(max(1, weeks.count))
        actualPerWeek = weeks.reduce(0) { $0 + $1.actual } / count
        projectedPerWeek = weeks.reduce(0) { $0 + $1.projected } / count
        var byPosition: [String: (total: Double, starts: Int)] = [:]
        var byStarter: [String: (name: String, gap: Double)] = [:]
        for starter in weeks.flatMap(\.starters) {
            let gap = starter.actual - starter.projected
            byStarter[starter.playerID, default: (starter.name, 0)].gap += gap
            if let position = starter.position {
                byPosition[position, default: (0, 0)].total += gap
                byPosition[position, default: (0, 0)].starts += 1
            }
        }
        gapByPosition = byPosition.map { ($0.key, $0.value.total / Double($0.value.starts)) }.sorted { $0.gap < $1.gap }
        gapByStarter = byStarter.values.map { ($0.name, $0.gap) }.sorted { $0.gap < $1.gap }
    }
}

/// Bye-week planning: how many starting slots a roster can't fill in a week.
public enum ByeWeekPlanner {
    /// Which positions can fill a lineup slot, across Sleeper's and ESPN's slot names.
    public static func positions(for slot: String) -> Set<String> {
        switch slot {
        case "FLEX": ["RB", "WR", "TE"]
        case "REC_FLEX", "WR/TE": ["WR", "TE"]
        case "WRRB_FLEX", "RB/WR": ["RB", "WR"]
        case "SUPER_FLEX", "OP": ["QB", "RB", "WR", "TE"]
        default: [slot]
        }
    }

    /// Slots left empty when the available players fill as many as they can (a maximum matching, so
    /// a TE isn't wasted at FLEX when he's needed at TE).
    public static func holes(slots: [String], available positions: [String]) -> Int {
        var slotOfPlayer = [Int?](repeating: nil, count: positions.count)
        var playerOfSlot = [Int?](repeating: nil, count: slots.count)
        func assign(_ slot: Int, _ seen: inout Set<Int>) -> Bool {
            let allowed = Self.positions(for: slots[slot])
            for player in positions.indices where allowed.contains(positions[player]) && seen.insert(player).inserted {
                if slotOfPlayer[player] == nil || assign(slotOfPlayer[player]!, &seen) {
                    slotOfPlayer[player] = slot
                    playerOfSlot[slot] = player
                    return true
                }
            }
            return false
        }
        for slot in slots.indices {
            var seen: Set<Int> = []
            _ = assign(slot, &seen)
        }
        return playerOfSlot.filter { $0 == nil }.count
    }
}

/// Who fills each starting slot in a week: starters keep their own slot where they can play, and the
/// bench fills the gaps (shuffling starters between flex slots if that frees a spot).
public struct LineupCover: Sendable {
    public struct Slot: Sendable {
        public let label: String
        /// The usual starter, nil when the slot is empty.
        public let starter: FantasyPlayer?
        /// Who plays there this week; nil when nobody on the roster can.
        public let filledBy: FantasyPlayer?

        /// The usual starter can't play here (or there isn't one).
        public var needsCover: Bool { starter == nil || filledBy?.id != starter?.id }
    }

    public let slots: [Slot]

    public var holes: Int { slots.filter { $0.filledBy == nil }.count }
    /// Slots whose usual starter is missing this week.
    public var changes: [Slot] { slots.filter(\.needsCover) }

    public init(lineup: [FantasyTeam.Slot], bench: [FantasyPlayer], isAvailable: (FantasyPlayer) -> Bool) {
        let starters = lineup.compactMap(\.player).filter(isAvailable)
        let players = starters + bench.filter { isAvailable($0) && !starters.contains($0) }
        var playerOfSlot = [Int?](repeating: nil, count: lineup.count)
        var slotOfPlayer = [Int?](repeating: nil, count: players.count)
        // Starters begin in their own slots.
        for (slot, entry) in lineup.enumerated() {
            if let starter = entry.player, let index = players.firstIndex(of: starter) {
                playerOfSlot[slot] = index
                slotOfPlayer[index] = slot
            }
        }
        // Then each open slot looks for someone, moving others along if needed (a maximum matching).
        func assign(_ slot: Int, _ seen: inout Set<Int>) -> Bool {
            let allowed = ByeWeekPlanner.positions(for: lineup[slot].label)
            // Free players first, so nobody already placed moves unless that's the only way to fill the slot.
            let order = players.indices.filter { slotOfPlayer[$0] == nil } + players.indices.filter { slotOfPlayer[$0] != nil }
            for player in order where allowed.contains(players[player].position ?? "") && seen.insert(player).inserted {
                if slotOfPlayer[player] == nil || assign(slotOfPlayer[player]!, &seen) {
                    slotOfPlayer[player] = slot
                    playerOfSlot[slot] = player
                    return true
                }
            }
            return false
        }
        for slot in lineup.indices where playerOfSlot[slot] == nil {
            var seen: Set<Int> = []
            _ = assign(slot, &seen)
        }
        slots = lineup.enumerated().map { index, entry in
            Slot(label: entry.label, starter: entry.player, filledBy: playerOfSlot[index].map { players[$0] })
        }
    }
}

/// ESPN's fantasy news feed for one player, and ESPN IDs for players a provider didn't link.
public enum ESPNNews {
    /// ESPN athlete IDs for players without one, by name within their NFL team's ESPN roster.
    public static func espnIDs(for players: [FantasyPlayer], session: URLSession = .shared) async -> [String: String] {
        let missing = Dictionary(grouping: players.filter { $0.espnID == nil && $0.team != nil && $0.position != "DEF" }, by: { $0.team! })
        return await withTaskGroup(of: [String: String].self) { group in
            for (team, players) in missing {
                group.addTask {
                    let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/\(team.lowercased())/roster")!
                    guard let (data, _) = try? await session.data(from: url), let roster = try? parseRoster(data) else { return [:] }
                    return players.reduce(into: [:]) { ids, player in
                        ids[player.id] = roster.first { Sleeper.sameName($0.name, player.name) }?.id
                    }
                }
            }
            return await group.reduce(into: [:]) { $0.merge($1) { a, _ in a } }
        }
    }

    static func parseRoster(_ data: Data) throws -> [(id: String, name: String)] {
        struct DTO: Decodable {
            struct Group: Decodable { struct Athlete: Decodable { let id: String; let fullName: String }; let items: [Athlete]? }
            let athletes: [Group]?
        }
        return (try JSONDecoder().decode(DTO.self, from: data).athletes ?? []).flatMap { $0.items ?? [] }.map { ($0.id, $0.fullName) }
    }

    public static func news(espnID: String, limit: Int = 4, session: URLSession = .shared) async throws -> [PlayerNews] {
        var url = URLComponents(string: "https://site.api.espn.com/apis/fantasy/v2/games/ffl/news/players")!
        url.queryItems = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "playerId", value: espnID)]
        let (data, _) = try await session.data(from: url.url!)
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [PlayerNews] {
        struct DTO: Decodable {
            struct Item: Decodable {
                struct Links: Decodable { struct Link: Decodable { let href: String? }; let web: Link?; let mobile: Link? }
                let id: Int?; let headline: String?; let story: String?; let published: String?; let type: String?; let links: Links?
            }
            let feed: [Item]?
        }
        let formatter = ISO8601DateFormatter()
        return (try JSONDecoder().decode(DTO.self, from: data).feed ?? []).compactMap { item in
            guard let headline = item.headline, let published = item.published.flatMap(formatter.date) else { return nil }
            return PlayerNews(id: item.id.map(String.init) ?? headline, headline: plainText(headline),
                              story: item.story.map(plainText).flatMap { $0.isEmpty ? nil : $0 }, published: published, source: item.type ?? "ESPN",
                              url: (item.links?.web?.href ?? item.links?.mobile?.href)
                                  .map { $0.replacingOccurrences(of: "http://", with: "https://") }.flatMap(URL.init(string:)))
        }
    }

    /// Some stories arrive as HTML (<p>, <photo>…): tags dropped, common entities decoded, spacing tidied.
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension FantasyData {
    /// Your starters' actual and projected points for each of the given weeks.
    public static func season(for league: FantasyLeagueRef, weeks: [Int], season: String,
                              espnCredentials: ESPNFantasy.Credentials?, playersCache: URL) async throws -> [FantasyWeekResult] {
        // Sleeper names starters by ID only; its player list fills in names, including players since dropped.
        let players = league.provider == .sleeper ? try await Sleeper.players(cache: playersCache) : [:]
        return try await withThrowingTaskGroup(of: FantasyWeekResult?.self) { group in
            for week in weeks {
                group.addTask {
                    switch league.provider {
                    case .sleeper: try await Sleeper.weekResult(leagueID: league.leagueID, userID: league.memberID, season: season,
                                                                week: week, players: players)
                    case .espn: try await ESPNFantasy.weekResult(leagueID: league.leagueID, season: season, teamID: league.memberID,
                                                                 week: week, credentials: espnCredentials)
                    case .yahoo: throw FantasyError.unsupported(.yahoo)
                    }
                }
            }
            var results: [FantasyWeekResult] = []
            for try await result in group { if let result { results.append(result) } }
            return results.sorted { $0.week < $1.week }
        }
    }

    public static func standings(for league: FantasyLeagueRef, season: String,
                                 espnCredentials: ESPNFantasy.Credentials?) async throws -> [FantasyStanding] {
        switch league.provider {
        case .sleeper: try await Sleeper.standings(leagueID: league.leagueID, userID: league.memberID)
        case .espn: try await ESPNFantasy.standings(leagueID: league.leagueID, season: season, teamID: league.memberID, credentials: espnCredentials)
        case .yahoo: throw FantasyError.unsupported(.yahoo)
        }
    }

    public static func calendar(for league: FantasyLeagueRef, season: String, state: Sleeper.State,
                                espnCredentials: ESPNFantasy.Credentials?) async throws -> FantasyCalendar {
        switch league.provider {
        case .sleeper: try await Sleeper.calendar(leagueID: league.leagueID)
        case .espn: try await ESPNFantasy.calendar(leagueID: league.leagueID, season: season, state: state, credentials: espnCredentials)
        case .yahoo: throw FantasyError.unsupported(.yahoo)
        }
    }
}

/// The weekly lineup overview prompt: only facts from the provider and ESPN news, nothing for the model to invent.
public enum FantasyPrompt {
    public static let weekSystem = """
    You brief a fantasy football manager on their week, for a sports app. Use only the data given: never invent \
    players, injuries, stats or news. In under 120 words of plain prose (no markdown, no lists), say where the matchup \
    stands, then each lineup issue listed and the bench options given for it (suggest only those; if none are given, \
    say a pickup is needed), then anything else in the news that affects this week. If there are no lineup issues, say so. \
    Write flowing sentences, never copy the data's labels or layout. For example: "You're projected 99.1 to 97.4, a 52% \
    chance. Your second RB slot is empty and nobody on your bench can fill it, so you'll need a pickup."
    """

    /// Can play this week: has an NFL team, isn't on bye, and isn't ruled out.
    static func isAvailable(_ player: FantasyPlayer, week: Int, byes: [String: Int]) -> Bool {
        guard let team = player.team, byes[team] != week else { return false }
        return (player.injury?.severity ?? 0) < 3
    }

    public static func week(team: FantasyTeam, week: Int, matchup: FantasyMatchup?, projections: [String: Double],
                            byes: [String: Int], news: [String: [PlayerNews]]) -> String {
        func describe(_ player: FantasyPlayer) -> String {
            var parts = ["\(player.name) (\([player.team, player.position].compactMap { $0 }.joined(separator: " ")))"]
            if let team = player.team, byes[team] == week { parts.append("ON BYE this week") }
            if player.team == nil { parts.append("no NFL team") }
            if let injury = player.injury { parts.append("status \(injury.status)" + (injury.detail.map { " (\($0))" } ?? "")) }
            if let projected = projections[player.id] { parts.append("projected \(String(format: "%.1f", projected))") }
            return parts.joined(separator: ", ")
        }
        var lines = ["Week \(week)"]
        if let matchup {
            if let opponent = matchup.opponent {
                lines.append("Matchup: \(matchup.me.teamName) projected \(String(format: "%.1f", matchup.me.projected)) vs "
                             + "\(opponent.teamName) projected \(String(format: "%.1f", opponent.projected))"
                             + (matchup.winProbability.map { ", win chance \(Int(($0 * 100).rounded()))%" } ?? ""))
            } else {
                lines.append("Matchup: bye week")
            }
        }
        lines.append("\nStarters:")
        lines += team.lineup.map { "- \($0.label): " + ($0.player.map(describe) ?? "EMPTY") }
        lines.append("\nBench:")
        lines += team.bench.map { "- " + describe($0) + (isAvailable($0, week: week, byes: byes) ? "" : ", UNAVAILABLE") }
        // Issues are worked out here, with only bench players who can actually fill each slot, so the model needn't reason it out.
        let issues = team.lineup.compactMap { slot -> String? in
            let problem: String
            if let player = slot.player {
                if isAvailable(player, week: week, byes: byes) {
                    guard player.injury?.severity == 2 else { return nil }
                    problem = "\(player.name) is doubtful"
                } else {
                    problem = player.team.flatMap { byes[$0] } == week ? "\(player.name) is on bye" : "\(player.name) is out"
                }
            } else {
                problem = "empty"
            }
            let eligible = ByeWeekPlanner.positions(for: slot.label)
            let options = team.bench
                .filter { isAvailable($0, week: week, byes: byes) && eligible.contains($0.position ?? "") }
                .sorted { (projections[$0.id] ?? 0) > (projections[$1.id] ?? 0) }
                .map { "\($0.name)" + (projections[$0.id].map { " (\(String(format: "%.1f", $0)))" } ?? "") }
            return "- \(slot.label): \(problem); bench options: " + (options.isEmpty ? "none" : options.joined(separator: ", "))
        }
        lines.append("\nLineup issues:")
        lines += issues.isEmpty ? ["- none"] : issues
        let recent = team.players.compactMap { player in news[player.id]?.first.map { (player, $0) } }
            .filter { $0.1.published > Date.now.addingTimeInterval(-5 * 24 * 3600) }
        if !recent.isEmpty {
            lines.append("\nRecent news:")
            lines += recent.map { "- \($0.0.name): \($0.1.headline)" }
        }
        return lines.joined(separator: "\n")
    }
}
