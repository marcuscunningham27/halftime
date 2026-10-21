import Foundation

/// Sleeper's public fantasy API (api.sleeper.app, read-only, no login): your NFL leagues, your roster,
/// and each player's fantasy points. Players carry their ESPN ID, which ties them to ESPN box scores.
public enum Sleeper {
    public struct FantasyLeague: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
    }

    public typealias Player = FantasyPlayer

    public static func headshotURL(espnID: String) -> URL? {
        URL(string: "https://a.espncdn.com/i/headshots/nfl/players/full/\(espnID).png")
    }

    /// Whether two spellings name the same player: case, punctuation and suffixes ignored,
    /// so Sleeper's "Kenneth Walker" matches ESPN's "Kenneth Walker III" and "D.J. Moore" matches "DJ Moore".
    public static func sameName(_ a: String, _ b: String) -> Bool {
        func key(_ name: String) -> String {
            let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "v"]
            return name.lowercased()
                .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
                .split(separator: " ").filter { !suffixes.contains(String($0)) }.joined(separator: " ")
        }
        return key(a) == key(b)
    }

    public struct Roster: Hashable, Sendable {
        public let players: [String]
        /// Starting lineup in slot order; nil where a slot is empty.
        public let lineup: [String?]
        public var starters: Set<String> { Set(lineup.compactMap { $0 }) }
        public var bench: [String] { players.filter { !starters.contains($0) } }
    }

    public struct State: Hashable, Sendable {
        public let season: String
        public let seasonStart: Date
    }

    static let base = URL(string: "https://api.sleeper.app/v1/")!

    // MARK: Requests

    public static func userID(username: String, session: URLSession = .shared) async throws -> String? {
        let name = username.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return try parseUserID(try await fetch("user/\(name)", session))
    }

    public static func leagues(userID: String, season: String, session: URLSession = .shared) async throws -> [FantasyLeague] {
        try parseLeagues(try await fetch("user/\(userID)/leagues/nfl/\(season)", session))
    }

    public static func state(session: URLSession = .shared) async throws -> State {
        try parseState(try await fetch("state/nfl", session))
    }

    public static func roster(leagueID: String, userID: String, session: URLSession = .shared) async throws -> Roster? {
        try parseRoster(try await fetch("league/\(leagueID)/rosters", session), userID: userID)
    }

    /// The league's starting slot labels in order ("QB", "RB", "FLEX"…), without bench, IR and taxi spots.
    public static func lineupSlots(leagueID: String, session: URLSession = .shared) async throws -> [String] {
        try parseLineupSlots(try await fetch("league/\(leagueID)", session))
    }

    /// Your lineup and bench in a league, or nil if you have no team in it.
    public static func team(leagueID: String, userID: String, playersCache: URL,
                            session: URLSession = .shared) async throws -> FantasyTeam? {
        async let rosterTask = roster(leagueID: leagueID, userID: userID, session: session)
        async let slotsTask = lineupSlots(leagueID: leagueID, session: session)
        async let playersTask = players(cache: playersCache, session: session)
        let (roster, slots, players) = try await (rosterTask, slotsTask, playersTask)
        guard let roster else { return nil }
        let filled = roster.lineup + Array(repeating: nil, count: max(0, slots.count - roster.lineup.count))
        return FantasyTeam(lineup: zip(slots, filled).map { .init(label: $0, player: $1.flatMap { players[$0] }) },
                           bench: roster.bench.compactMap { players[$0] })
    }

    /// Projections for a week scored the way Sleeper's app does it: each projected stat times the
    /// league's own scoring rule for it, so totals match Sleeper exactly.
    public static func projections(leagueID: String, season: String, week: Int,
                                   session: URLSession = .shared) async throws -> [String: Double] {
        let scoring = try parseScoring(try await fetch("league/\(leagueID)", session))
        // Projections live on Sleeper's newer, undocumented host.
        var url = URLComponents(string: "https://api.sleeper.com/projections/nfl/\(season)/\(week)")!
        url.queryItems = [URLQueryItem(name: "season_type", value: "regular")]
            + ["QB", "RB", "WR", "TE", "K", "DEF"].map { URLQueryItem(name: "position[]", value: $0) }
        let (data, _) = try await session.data(from: url.url!)
        return try parseProjections(data, scoring: scoring)
    }

    /// Your matchup this week: both rosters' managers and team names, points so far, and projected totals of the starters.
    public static func matchup(leagueID: String, userID: String, week: Int, projections: [String: Double],
                               session: URLSession = .shared) async throws -> FantasyMatchup? {
        async let rostersData = fetch("league/\(leagueID)/rosters", session)
        async let usersData = fetch("league/\(leagueID)/users", session)
        async let matchupsData = fetch("league/\(leagueID)/matchups/\(week)", session)
        return try parseMatchup(rosters: try await rostersData, users: try await usersData, matchups: try await matchupsData,
                                userID: userID, projections: projections)
    }

    /// Your starters in one week with what each scored (Sleeper's starters_points) and was projected.
    public static func weekResult(leagueID: String, userID: String, season: String, week: Int, players: [String: Player],
                                  session: URLSession = .shared) async throws -> FantasyWeekResult? {
        async let rostersData = fetch("league/\(leagueID)/rosters", session)
        async let matchupsData = fetch("league/\(leagueID)/matchups/\(week)", session)
        async let projectionsTask = projections(leagueID: leagueID, season: season, week: week, session: session)
        return try parseWeekResult(rosters: try await rostersData, matchups: try await matchupsData, userID: userID,
                                   week: week, projections: try await projectionsTask, players: players)
    }

    public static func standings(leagueID: String, userID: String, session: URLSession = .shared) async throws -> [FantasyStanding] {
        async let rostersData = fetch("league/\(leagueID)/rosters", session)
        async let usersData = fetch("league/\(leagueID)/users", session)
        return try parseStandings(rosters: try await rostersData, users: try await usersData, userID: userID)
    }

    public static func calendar(leagueID: String, session: URLSession = .shared) async throws -> FantasyCalendar {
        try parseCalendar(try await fetch("league/\(leagueID)", session))
    }

    /// Fantasy points per player ID for one week, across every team in the league.
    public static func points(leagueID: String, week: Int, session: URLSession = .shared) async throws -> [String: Double] {
        try parsePoints(try await fetch("league/\(leagueID)/matchups/\(week)", session))
    }

    /// Every NFL player, slimmed and cached on disk for three hours (the full list is ~15 MB; injuries change daily).
    public static func players(cache: URL, session: URLSession = .shared) async throws -> [String: Player] {
        if let modified = try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           modified.timeIntervalSinceNow > -3 * 3600,
           let players = try? JSONDecoder().decode([String: Player].self, from: Data(contentsOf: cache)) {
            return players
        }
        let players = try parsePlayers(try await fetch("players/nfl", session))
        try? JSONEncoder().encode(players).write(to: cache, options: .atomic)
        return players
    }

    /// The NFL week a game falls in: weeks run seven days from the season's start date.
    public static func week(of date: Date, state: State) -> Int {
        max(1, Int(date.timeIntervalSince(state.seasonStart) / (7 * 24 * 3600)) + 1)
    }

    private static func fetch(_ path: String, _ session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: base.appending(path: path))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        return data
    }

    // MARK: Parsing

    static func parseUserID(_ data: Data) throws -> String? {
        // An unknown username comes back as JSON null.
        struct User: Decodable { let user_id: String }
        return try JSONDecoder().decode(User?.self, from: data)?.user_id
    }

    static func parseLeagues(_ data: Data) throws -> [FantasyLeague] {
        struct DTO: Decodable { let league_id: String; let name: String }
        return try JSONDecoder().decode([DTO].self, from: data).map { .init(id: $0.league_id, name: $0.name) }
    }

    static func parseState(_ data: Data) throws -> State {
        struct DTO: Decodable { let season: String; let season_start_date: String }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: dto.season_start_date) else { throw URLError(.cannotParseResponse) }
        return State(season: dto.season, seasonStart: start)
    }

    static func parseRoster(_ data: Data, userID: String) throws -> Roster? {
        struct DTO: Decodable { let owner_id: String?; let co_owners: [String]?; let players: [String]?; let starters: [String]? }
        guard let mine = try JSONDecoder().decode([DTO].self, from: data)
            .first(where: { $0.owner_id == userID || ($0.co_owners ?? []).contains(userID) })
        else { return nil }
        // "0" marks an empty starting slot.
        return Roster(players: mine.players ?? [], lineup: (mine.starters ?? []).map { $0 == "0" ? nil : $0 })
    }

    static func parseLineupSlots(_ data: Data) throws -> [String] {
        struct DTO: Decodable { let roster_positions: [String]? }
        let reserve: Set<String> = ["BN", "IR", "TAXI"]
        return (try JSONDecoder().decode(DTO.self, from: data).roster_positions ?? []).filter { !reserve.contains($0) }
    }

    static func parsePoints(_ data: Data) throws -> [String: Double] {
        struct DTO: Decodable { let players_points: [String: Double]? }
        return try JSONDecoder().decode([DTO].self, from: data)
            .reduce(into: [:]) { all, team in all.merge(team.players_points ?? [:]) { $1 } }
    }

    /// The league's points per stat, e.g. ["pass_yd": 0.04, "rec": 0.5, "rush_td": 6].
    static func parseScoring(_ data: Data) throws -> [String: Double] {
        struct DTO: Decodable { let scoring_settings: [String: Double]? }
        return try JSONDecoder().decode(DTO.self, from: data).scoring_settings ?? [:]
    }

    static func parseProjections(_ data: Data, scoring: [String: Double]) throws -> [String: Double] {
        struct DTO: Decodable { let player_id: String; let stats: [String: Double?]? }
        return try JSONDecoder().decode([DTO].self, from: data).reduce(into: [:]) { all, entry in
            guard let stats = entry.stats else { return }
            all[entry.player_id] = scoring.reduce(0) { total, rule in total + rule.value * ((stats[rule.key] ?? 0) ?? 0) }
        }
    }

    static func parseMatchup(rosters: Data, users: Data, matchups: Data, userID: String,
                             projections: [String: Double]) throws -> FantasyMatchup? {
        struct Roster: Decodable { let roster_id: Int; let owner_id: String?; let co_owners: [String]? }
        struct User: Decodable {
            struct Metadata: Decodable { let team_name: String?; let avatar: String? }
            let user_id: String; let display_name: String?; let avatar: String?; let metadata: Metadata?
        }
        struct Matchup: Decodable { let roster_id: Int; let matchup_id: Int?; let points: Double?; let starters: [String]? }
        let decoder = JSONDecoder()
        let rosters = try decoder.decode([Roster].self, from: rosters)
        let users = Dictionary(try decoder.decode([User].self, from: users).map { ($0.user_id, $0) }, uniquingKeysWith: { a, _ in a })
        let matchups = try decoder.decode([Matchup].self, from: matchups)
        guard let mine = rosters.first(where: { $0.owner_id == userID || ($0.co_owners ?? []).contains(userID) }),
              let myMatchup = matchups.first(where: { $0.roster_id == mine.roster_id })
        else { return nil }
        func side(_ matchup: Matchup) -> FantasyMatchup.Side {
            let owner = rosters.first { $0.roster_id == matchup.roster_id }?.owner_id.flatMap { users[$0] }
            let avatar = owner?.metadata?.avatar.flatMap(URL.init(string:))
                ?? owner?.avatar.flatMap { URL(string: "https://sleepercdn.com/avatars/thumbs/\($0)") }
            let manager = owner?.display_name
            return .init(teamName: owner?.metadata?.team_name ?? manager.map { "Team \($0)" } ?? "Team \(matchup.roster_id)",
                         manager: manager, avatarURL: avatar, points: matchup.points ?? 0,
                         projected: (matchup.starters ?? []).reduce(0) { $0 + (projections[$1] ?? 0) })
        }
        let opponent = myMatchup.matchup_id.flatMap { id in
            matchups.first { $0.matchup_id == id && $0.roster_id != mine.roster_id }
        }
        return FantasyMatchup(me: side(myMatchup), opponent: opponent.map(side))
    }

    static func parseWeekResult(rosters: Data, matchups: Data, userID: String, week: Int,
                                projections: [String: Double], players: [String: Player]) throws -> FantasyWeekResult? {
        struct Roster: Decodable { let roster_id: Int; let owner_id: String?; let co_owners: [String]? }
        struct Matchup: Decodable { let roster_id: Int; let starters: [String]?; let starters_points: [Double]? }
        let decoder = JSONDecoder()
        guard let mine = try decoder.decode([Roster].self, from: rosters)
            .first(where: { $0.owner_id == userID || ($0.co_owners ?? []).contains(userID) }),
              let matchup = try decoder.decode([Matchup].self, from: matchups).first(where: { $0.roster_id == mine.roster_id })
        else { return nil }
        let starters = zip(matchup.starters ?? [], matchup.starters_points ?? [])
            .filter { $0.0 != "0" }
            .map { FantasyWeekResult.Starter(playerID: $0.0, name: players[$0.0]?.name ?? $0.0, position: players[$0.0]?.position,
                                             actual: $0.1, projected: projections[$0.0] ?? 0) }
        return FantasyWeekResult(week: week, starters: starters)
    }

    static func parseStandings(rosters: Data, users: Data, userID: String) throws -> [FantasyStanding] {
        struct Roster: Decodable {
            struct Settings: Decodable { let wins: Int?; let losses: Int?; let ties: Int?; let fpts: Int?; let fpts_decimal: Int? }
            let roster_id: Int; let owner_id: String?; let co_owners: [String]?; let settings: Settings?
        }
        struct User: Decodable {
            struct Metadata: Decodable { let team_name: String? }
            let user_id: String; let display_name: String?; let metadata: Metadata?
        }
        let decoder = JSONDecoder()
        let users = Dictionary(try decoder.decode([User].self, from: users).map { ($0.user_id, $0) }, uniquingKeysWith: { a, _ in a })
        return try decoder.decode([Roster].self, from: rosters).map { roster in
            let owner = roster.owner_id.flatMap { users[$0] }
            let points = Double(roster.settings?.fpts ?? 0) + Double(roster.settings?.fpts_decimal ?? 0) / 100
            return FantasyStanding(id: String(roster.roster_id),
                                   teamName: owner?.metadata?.team_name ?? owner?.display_name ?? "Team \(roster.roster_id)",
                                   wins: roster.settings?.wins ?? 0, losses: roster.settings?.losses ?? 0, ties: roster.settings?.ties ?? 0,
                                   pointsFor: points, isMine: roster.owner_id == userID || (roster.co_owners ?? []).contains(userID))
        }
    }

    static func parseCalendar(_ data: Data) throws -> FantasyCalendar {
        struct DTO: Decodable { struct Settings: Decodable { let playoff_week_start: Int?; let trade_deadline: Int? }; let settings: Settings? }
        let settings = try JSONDecoder().decode(DTO.self, from: data).settings
        // A deadline past the regular season (Sleeper uses 99) means there isn't one.
        let deadline = settings?.trade_deadline.flatMap { $0 > 0 && $0 < 19 ? $0 : nil }
        return FantasyCalendar(playoffWeekStart: settings?.playoff_week_start ?? 15, tradeDeadlineWeek: deadline)
    }

    static func parsePlayers(_ data: Data) throws -> [String: Player] {
        struct DTO: Decodable {
            let full_name: String?; let first_name: String?; let last_name: String?
            let position: String?; let team: String?; let espn_id: Int?
            let injury_status: String?; let injury_body_part: String?; let practice_participation: String?
        }
        return try JSONDecoder().decode([String: DTO].self, from: data).reduce(into: [:]) { all, entry in
            let (id, dto) = entry
            let name = dto.full_name ?? [dto.first_name, dto.last_name].compactMap { $0 }.joined(separator: " ")
            let espnID = dto.espn_id.map(String.init)
            // Sleeper has a photo for every player; ESPN's are used where Sleeper knows the ESPN ID.
            all[id] = Player(id: id, name: name, position: dto.position, team: dto.team.map(espnTeam), espnID: espnID,
                             photoURL: espnID.flatMap(headshotURL) ?? URL(string: "https://sleepercdn.com/content/nfl/players/thumb/\(id).jpg"),
                             injury: dto.injury_status.map { status in
                                 let practice = dto.practice_participation.map { "\($0) practice" }
                                 let detail = [dto.injury_body_part, practice].compactMap { $0 }.joined(separator: " · ")
                                 return .init(status: status, detail: detail.isEmpty ? nil : detail)
                             })
        }
    }

    /// Sleeper and ESPN agree on NFL abbreviations except Washington.
    static func espnTeam(_ sleeper: String) -> String {
        sleeper == "WAS" ? "WSH" : sleeper
    }
}
