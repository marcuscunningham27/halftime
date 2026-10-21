import Foundation

/// ESPN Fantasy Football's league API (lm-api-reads.fantasy.espn.com). Public leagues need only the
/// league ID; private ones also need the espn_s2 and SWID cookies from a signed-in browser.
/// Player IDs are ESPN athlete IDs, so photos and box scores line up directly.
public enum ESPNFantasy {
    public struct Credentials: Codable, Hashable, Sendable {
        public let espnS2: String
        public let swid: String

        public init(espnS2: String, swid: String) {
            self.espnS2 = espnS2.trimmingCharacters(in: .whitespacesAndNewlines)
            self.swid = swid.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public struct LeagueInfo: Sendable {
        public let name: String
        public let teams: [(id: String, name: String)]
    }

    public enum ESPNFantasyError: LocalizedError {
        case privateLeague, notFound

        public var errorDescription: String? {
            switch self {
            case .privateLeague: "This league is private. Add your espn_s2 and SWID cookies to read it."
            case .notFound: "No ESPN league with that ID this season."
            }
        }
    }

    // MARK: Requests

    /// The league's name and teams, for choosing which team is yours.
    public static func league(leagueID: String, season: String, credentials: Credentials?,
                              session: URLSession = .shared) async throws -> LeagueInfo {
        try parseLeague(try await fetch(leagueID, season, ["mTeam", "mSettings"], nil, credentials, session))
    }

    public static func team(leagueID: String, season: String, teamID: String, credentials: Credentials?,
                            session: URLSession = .shared) async throws -> FantasyTeam? {
        try parseTeam(try await fetch(leagueID, season, ["mRoster", "mSettings"], nil, credentials, session), teamID: teamID)
    }

    /// Points per player for one week (ESPN's scoring period), across the league's rosters.
    public static func points(leagueID: String, season: String, week: Int, credentials: Credentials?,
                              session: URLSession = .shared) async throws -> [String: Double] {
        try parsePoints(try await fetch(leagueID, season, ["mRoster"], week, credentials, session), week: week)
    }

    /// ESPN's own projections for one week (its source 1), in the league's scoring.
    public static func projections(leagueID: String, season: String, week: Int, credentials: Credentials?,
                                   session: URLSession = .shared) async throws -> [String: Double] {
        try parsePoints(try await fetch(leagueID, season, ["mRoster"], week, credentials, session), week: week, source: 1)
    }

    public static func matchup(leagueID: String, season: String, teamID: String, week: Int, projections: [String: Double],
                               credentials: Credentials?, session: URLSession = .shared) async throws -> FantasyMatchup? {
        try parseMatchup(try await fetch(leagueID, season, ["mMatchupScore", "mRoster", "mTeam"], week, credentials, session),
                         teamID: teamID, week: week, projections: projections)
    }

    public static func weekResult(leagueID: String, season: String, teamID: String, week: Int, credentials: Credentials?,
                                  session: URLSession = .shared) async throws -> FantasyWeekResult? {
        try parseWeekResult(try await fetch(leagueID, season, ["mRoster"], week, credentials, session), teamID: teamID, week: week)
    }

    public static func standings(leagueID: String, season: String, teamID: String, credentials: Credentials?,
                                 session: URLSession = .shared) async throws -> [FantasyStanding] {
        try parseStandings(try await fetch(leagueID, season, ["mTeam"], nil, credentials, session), teamID: teamID)
    }

    public static func calendar(leagueID: String, season: String, state: Sleeper.State, credentials: Credentials?,
                                session: URLSession = .shared) async throws -> FantasyCalendar {
        try parseCalendar(try await fetch(leagueID, season, ["mSettings"], nil, credentials, session), state: state)
    }

    private static func fetch(_ leagueID: String, _ season: String, _ views: [String], _ week: Int?,
                              _ credentials: Credentials?, _ session: URLSession) async throws -> Data {
        var url = URLComponents(string: "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/\(season)/segments/0/leagues/\(leagueID)")!
        url.queryItems = views.map { URLQueryItem(name: "view", value: $0) } + (week.map { [URLQueryItem(name: "scoringPeriodId", value: String($0))] } ?? [])
        var request = URLRequest(url: url.url!)
        if let credentials {
            request.setValue("espn_s2=\(credentials.espnS2); SWID=\(credentials.swid)", forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 401: throw ESPNFantasyError.privateLeague
        case 404: throw ESPNFantasyError.notFound
        default: throw URLError(.badServerResponse)
        }
    }

    // MARK: Parsing

    private struct LeagueDTO: Decodable {
        struct Settings: Decodable {
            struct RosterSettings: Decodable { let lineupSlotCounts: [String: Int]? }
            struct ScheduleSettings: Decodable { let matchupPeriodCount: Int? }
            struct TradeSettings: Decodable { let deadlineDate: Double? }
            let name: String?
            let rosterSettings: RosterSettings?
            let scheduleSettings: ScheduleSettings?
            let tradeSettings: TradeSettings?
        }
        struct Team: Decodable {
            struct Roster: Decodable { let entries: [Entry]? }
            let id: Int
            let name: String?
            let location: String?
            let nickname: String?
            let roster: Roster?
            let logo: String?
            let owners: [String]?
            let record: Record?
        }
        struct Record: Decodable {
            struct Overall: Decodable { let wins: Int?; let losses: Int?; let ties: Int?; let pointsFor: Double? }
            let overall: Overall?
        }
        struct Entry: Decodable {
            struct PoolEntry: Decodable { let player: Player }
            let lineupSlotId: Int
            let playerPoolEntry: PoolEntry?
        }
        struct Player: Decodable {
            struct Stat: Decodable { let scoringPeriodId: Int?; let statSourceId: Int?; let appliedTotal: Double? }
            let id: Int
            let fullName: String
            let defaultPositionId: Int?
            let proTeamId: Int?
            let stats: [Stat]?
            let injuryStatus: String?
        }
        struct Member: Decodable { let id: String; let displayName: String? }
        struct Matchup: Decodable {
            struct Side: Decodable { let teamId: Int; let totalPoints: Double? }
            let matchupPeriodId: Int?
            let home: Side?
            let away: Side?
        }
        let settings: Settings?
        let teams: [Team]?
        let members: [Member]?
        let schedule: [Matchup]?
    }

    static func parseLeague(_ data: Data) throws -> LeagueInfo {
        let dto = try JSONDecoder().decode(LeagueDTO.self, from: data)
        let teams = (dto.teams ?? []).map { team in
            // Newer leagues have one name; older ones split it into location and nickname.
            (id: String(team.id), name: team.name ?? [team.location, team.nickname].compactMap { $0 }.joined(separator: " "))
        }
        return LeagueInfo(name: dto.settings?.name ?? "ESPN League", teams: teams)
    }

    static func parseTeam(_ data: Data, teamID: String) throws -> FantasyTeam? {
        let dto = try JSONDecoder().decode(LeagueDTO.self, from: data)
        guard let team = dto.teams?.first(where: { String($0.id) == teamID }) else { return nil }
        let entries = team.roster?.entries ?? []
        let counts = dto.settings?.rosterSettings?.lineupSlotCounts ?? [:]
        var lineup: [FantasyTeam.Slot] = []
        for (slotID, label) in startingSlots {
            let filled = entries.filter { $0.lineupSlotId == slotID }.compactMap { $0.playerPoolEntry.map { player($0.player) } }
            let count = max(counts[String(slotID)] ?? 0, filled.count)
            lineup += (0..<count).map { FantasyTeam.Slot(label: label, player: $0 < filled.count ? filled[$0] : nil) }
        }
        let starting = Set(startingSlots.map(\.id))
        let bench = entries.filter { !starting.contains($0.lineupSlotId) }.compactMap { $0.playerPoolEntry.map { player($0.player) } }
        return FantasyTeam(lineup: lineup, bench: bench)
    }

    /// Points per player for a week: actual (source 0) or ESPN's projection (source 1).
    static func parsePoints(_ data: Data, week: Int, source: Int = 0) throws -> [String: Double] {
        let dto = try JSONDecoder().decode(LeagueDTO.self, from: data)
        var points: [String: Double] = [:]
        for entry in (dto.teams ?? []).flatMap({ $0.roster?.entries ?? [] }) {
            guard let player = entry.playerPoolEntry?.player,
                  let total = player.stats?.first(where: { $0.scoringPeriodId == week && $0.statSourceId == source })?.appliedTotal
            else { continue }
            points[String(player.id)] = total
        }
        return points
    }

    static func parseMatchup(_ data: Data, teamID: String, week: Int, projections: [String: Double]) throws -> FantasyMatchup? {
        let dto = try JSONDecoder().decode(LeagueDTO.self, from: data)
        guard let id = Int(teamID),
              let game = dto.schedule?.first(where: { $0.matchupPeriodId == week && ($0.home?.teamId == id || $0.away?.teamId == id) })
        else { return nil }
        let members = Dictionary((dto.members ?? []).map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let benchSlots: Set<Int> = [20, 21]
        func side(_ side: LeagueDTO.Matchup.Side) -> FantasyMatchup.Side {
            let team = dto.teams?.first { $0.id == side.teamId }
            let starters = (team?.roster?.entries ?? []).filter { !benchSlots.contains($0.lineupSlotId) }
            return .init(teamName: team?.name ?? [team?.location, team?.nickname].compactMap { $0 }.joined(separator: " "),
                         manager: team?.owners?.first.flatMap { members[$0] ?? nil },
                         avatarURL: team?.logo.flatMap(URL.init(string:)), points: side.totalPoints ?? 0,
                         projected: starters.reduce(0) { total, entry in
                             total + (entry.playerPoolEntry.map { projections[String($0.player.id)] ?? 0 } ?? 0)
                         })
        }
        let mine = game.home?.teamId == id ? game.home : game.away
        let theirs = game.home?.teamId == id ? game.away : game.home
        return mine.map { FantasyMatchup(me: side($0), opponent: theirs.map(side)) }
    }

    static func parseWeekResult(_ data: Data, teamID: String, week: Int) throws -> FantasyWeekResult? {
        let dto = try JSONDecoder().decode(LeagueDTO.self, from: data)
        guard let team = dto.teams?.first(where: { String($0.id) == teamID }) else { return nil }
        let starting = Set(startingSlots.map(\.id))
        let starters = (team.roster?.entries ?? []).filter { starting.contains($0.lineupSlotId) }.compactMap { entry -> FantasyWeekResult.Starter? in
            guard let player = entry.playerPoolEntry?.player else { return nil }
            func total(_ source: Int) -> Double {
                player.stats?.first { $0.scoringPeriodId == week && $0.statSourceId == source }?.appliedTotal ?? 0
            }
            return .init(playerID: String(player.id), name: player.fullName, position: player.defaultPositionId.flatMap { positions[$0] },
                         actual: total(0), projected: total(1))
        }
        return FantasyWeekResult(week: week, starters: starters)
    }

    static func parseStandings(_ data: Data, teamID: String) throws -> [FantasyStanding] {
        (try JSONDecoder().decode(LeagueDTO.self, from: data).teams ?? []).map { team in
            let record = team.record?.overall
            return FantasyStanding(id: String(team.id), teamName: team.name ?? [team.location, team.nickname].compactMap { $0 }.joined(separator: " "),
                                   wins: record?.wins ?? 0, losses: record?.losses ?? 0, ties: record?.ties ?? 0,
                                   pointsFor: record?.pointsFor ?? 0, isMine: String(team.id) == teamID)
        }
    }

    static func parseCalendar(_ data: Data, state: Sleeper.State) throws -> FantasyCalendar {
        let settings = try JSONDecoder().decode(LeagueDTO.self, from: data).settings
        let deadline = settings?.tradeSettings?.deadlineDate.flatMap { $0 > 0 ? Sleeper.week(of: Date(timeIntervalSince1970: $0 / 1000), state: state) : nil }
        return FantasyCalendar(playoffWeekStart: (settings?.scheduleSettings?.matchupPeriodCount ?? 14) + 1, tradeDeadlineWeek: deadline)
    }

    private static func player(_ dto: LeagueDTO.Player) -> FantasyPlayer {
        // Team defences have negative IDs, which aren't athletes.
        let espnID = dto.id > 0 ? String(dto.id) : nil
        return FantasyPlayer(id: String(dto.id), name: dto.fullName, position: dto.defaultPositionId.flatMap { positions[$0] },
                             team: dto.proTeamId.flatMap { proTeams[$0] }, espnID: espnID,
                             photoURL: espnID.flatMap(Sleeper.headshotURL),
                             injury: dto.injuryStatus.flatMap { status in
                                 // ESPN says ACTIVE (or NORMAL) for healthy players.
                                 ["ACTIVE", "NORMAL"].contains(status) ? nil
                                     : .init(status: status == "INJURY_RESERVE" ? "IR" : status.capitalized, detail: nil)
                             })
    }

    /// ESPN lineup slot IDs in display order; bench (20) and IR (21) aren't starting slots.
    static let startingSlots: [(id: Int, label: String)] = [
        (0, "QB"), (2, "RB"), (3, "RB/WR"), (4, "WR"), (5, "WR/TE"), (6, "TE"), (23, "FLEX"), (7, "OP"), (16, "DEF"), (17, "K"),
    ]

    static let positions: [Int: String] = [1: "QB", 2: "RB", 3: "WR", 4: "TE", 5: "K", 16: "DEF"]

    /// ESPN Fantasy's pro team IDs to ESPN's NFL abbreviations.
    static let proTeams: [Int: String] = [
        1: "ATL", 2: "BUF", 3: "CHI", 4: "CIN", 5: "CLE", 6: "DAL", 7: "DEN", 8: "DET", 9: "GB", 10: "TEN", 11: "IND",
        12: "KC", 13: "LV", 14: "LAR", 15: "MIA", 16: "MIN", 17: "NE", 18: "NO", 19: "NYG", 20: "NYJ", 21: "PHI",
        22: "ARI", 23: "PIT", 24: "LAC", 25: "SF", 26: "SEA", 27: "TB", 28: "WSH", 29: "CAR", 30: "JAX", 33: "BAL", 34: "HOU",
    ]
}
