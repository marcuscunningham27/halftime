import Foundation

public enum ESPNError: Error {
    case unsupportedLeague(League.ID)
    case badStatus(Int)
}

public actor ESPNProvider: SportsProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func leagues() -> [League] {
        League.all.filter { ESPNEndpoints.leaguePaths[$0.id] != nil }
    }

    public func scoreboard(league: League, date: Date) async throws -> [Game] {
        try await scoreboard(league: league, date: date, cachePolicy: .useProtocolCachePolicy)
    }

    /// The same request answered only from URLSession's disk cache (whatever was saved last launch), never the network.
    public func cachedScoreboard(league: League, date: Date) async -> [Game] {
        (try? await scoreboard(league: league, date: date, cachePolicy: .returnCacheDataDontLoad)) ?? []
    }

    private func scoreboard(league: League, date: Date, cachePolicy: URLRequest.CachePolicy) async throws -> [Game] {
        let path = try Self.path(for: league.id)
        let day = Calendar.current.dateInterval(of: .day, for: date)!
        var games: [Game] = []
        for espnDay in ESPNEndpoints.espnDays(covering: day) {
            let data = try await fetch(URLRequest(url: ESPNEndpoints.scoreboard(path: path, espnDay: espnDay), cachePolicy: cachePolicy))
            games += try Self.parseScoreboard(data, leagueID: league.id)
        }
        return games.filter { $0.startDate >= day.start && $0.startDate < day.end }
    }

    /// Every game in one NFL regular-season week, in a single request.
    public static func nflWeek(season: String, week: Int, session: URLSession = .shared) async throws -> [Game] {
        let (data, _) = try await session.data(from: ESPNEndpoints.nflWeek(season: season, week: week))
        return try parseScoreboard(data, leagueID: League.nfl.id)
    }

    /// The week each NFL team (by abbreviation) has off, from the regular-season weeks given.
    public static func nflByes(season: String, weeks: ClosedRange<Int> = 1...18, session: URLSession = .shared) async throws -> [String: Int] {
        let schedule = try await withThrowingTaskGroup(of: (Int, [Game]).self) { group in
            for week in weeks { group.addTask { (week, try await nflWeek(season: season, week: week, session: session)) } }
            var all: [Int: [Game]] = [:]
            for try await (week, games) in group { all[week] = games }
            return all
        }
        return byes(in: schedule)
    }

    static func byes(in schedule: [Int: [Game]]) -> [String: Int] {
        let teams = Set(schedule.values.flatMap { $0.flatMap { [$0.away.team.abbreviation, $0.home.team.abbreviation] } })
        var byes: [String: Int] = [:]
        for (week, games) in schedule {
            let playing = Set(games.flatMap { [$0.away.team.abbreviation, $0.home.team.abbreviation] })
            for team in teams.subtracting(playing) { byes[team] = week }
        }
        return byes
    }

    public func recentResults(league: League, before date: Date) async throws -> [Game] {
        let path = try Self.path(for: league.id)
        var finals = try Self.parseScoreboard(try await fetch(ESPNEndpoints.scoreboard(path: path, espnDay: nil)), leagueID: league.id)
            .filter { $0.status == .final }
        // The current slate can be all upcoming (NBA early in the day), so step back a day at a time, up to a week.
        // Neighbouring local days share an ESPN day, so skip ones already fetched.
        var day = date, fetched: Set<String> = []
        for _ in 0..<7 where finals.isEmpty {
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
            let interval = Calendar.current.dateInterval(of: .day, for: day)!
            for espnDay in ESPNEndpoints.espnDays(covering: interval) where fetched.insert(espnDay).inserted {
                finals += try Self.parseScoreboard(try await fetch(ESPNEndpoints.scoreboard(path: path, espnDay: espnDay)), leagueID: league.id)
                    .filter { $0.status == .final }
            }
        }
        return finals.sorted { $0.startDate > $1.startDate }
    }

    public func featuredGame(for team: Follows.TeamRef) async throws -> Game? {
        let path = try Self.path(for: team.leagueID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.dateStrategy
        let events = try decoder.decode(ScheduleDTO.self, from: try await fetch(ESPNEndpoints.schedule(path: path, teamID: team.teamID))).events
        let picked = Self.featuredIndex(events.map { ($0.date, $0.competitions.first?.status.type.state) }, now: .now)
        guard let pick = picked.map({ events[$0] }) else { return nil }
        // The schedule has no live scores, so take the full game from that day's scoreboard.
        guard let league = League.with(id: team.leagueID) else { return nil }
        return try await scoreboard(league: league, date: pick.date).first { $0.id == pick.id }
    }

    /// Which of a team's games to feature: live, else one that finished in the last 36 hours (so today's
    /// result isn't hidden by the next fixture), else the next one, else the latest result.
    static func featuredIndex(_ games: [(date: Date, state: String?)], now: Date) -> Int? {
        let indices = games.indices
        let finals = indices.filter { games[$0].state == "post" }
        let latestFinal = finals.max { games[$0].date < games[$1].date }
        if let live = indices.first(where: { games[$0].state == "in" }) { return live }
        if let latestFinal, now.timeIntervalSince(games[latestFinal].date) < 36 * 3600 { return latestFinal }
        return indices.filter { games[$0].state == "pre" }.min { games[$0].date < games[$1].date } ?? latestFinal
    }

    public func standings(league: League) async throws -> Standings {
        let path = try Self.path(for: league.id)
        // College football has conference tables; the app shows the AP poll instead, which also limits search to it.
        if league == .cfb { return try Self.parseRankings(try await fetch(ESPNEndpoints.rankings(path: path))) }
        guard let spec = ESPNEndpoints.standingsSpecs[league.id] else { throw ESPNError.unsupportedLeague(league.id) }
        return try Self.parseStandings(try await fetch(ESPNEndpoints.standings(path: path, level: spec.level)), spec: spec)
    }

    /// The AP Top 25 as a one-table standings: record and poll points.
    static func parseRankings(_ data: Data) throws -> Standings {
        let polls = try JSONDecoder().decode(RankingsDTO.self, from: data).rankings
        guard let ap = polls.first(where: { $0.type == "ap" }) ?? polls.first else { return Standings(columns: [], groups: []) }
        return Standings(columns: ["REC", "PTS"], groups: [Standings.Group(name: ap.name ?? "AP Top 25", entries: ap.ranks.map { rank in
            Standings.Entry(team: rank.team.team, values: [rank.recordSummary ?? "–", rank.points.map { String(Int($0)) } ?? "–"])
        })])
    }

    static func parseStandings(_ data: Data, spec: ESPNEndpoints.StandingsSpec) throws -> Standings {
        // Groups are whichever nodes carry entries: conferences, divisions, or the whole league.
        func groups(_ node: StandingsNodeDTO) -> [Standings.Group] {
            guard let entries = node.standings?.entries else { return (node.children ?? []).flatMap(groups) }
            let ranked = entries.sorted { a, b in
                for stat in spec.rankBy {
                    let x = a.value(stat) ?? -.infinity, y = b.value(stat) ?? -.infinity
                    if x != y { return x > y }
                }
                return false
            }
            return [Standings.Group(name: node.name ?? "", entries: ranked.map { entry in
                Standings.Entry(team: entry.team.team, values: spec.columns.map { entry.display($0.stat) ?? "–" })
            })]
        }
        let root = try JSONDecoder().decode(StandingsNodeDTO.self, from: data)
        return Standings(columns: spec.columns.map(\.label), groups: groups(root))
    }

    /// Per-play win, cover and over chances from ESPN's core API.
    public func probabilities(for game: Game) async throws -> [ProbabilityPoint] {
        let path = try Self.path(for: game.leagueID)
        return try Self.parseProbabilities(try await fetch(ESPNEndpoints.probabilities(path: path, gameID: game.id)))
    }

    static func parseProbabilities(_ data: Data) throws -> [ProbabilityPoint] {
        struct Page: Decodable {
            struct Item: Decodable {
                struct Ref: Decodable { let ref: String; enum CodingKeys: String, CodingKey { case ref = "$ref" } }
                let play: Ref?
                let homeWinPercentage: Double?
                let spreadCoverProbHome: Double?
                let totalOverProb: Double?
            }
            let items: [Item]
        }
        return try JSONDecoder().decode(Page.self, from: data).items.compactMap { item in
            // ".../plays/4018730081?lang=en" → "4018730081"
            guard let ref = item.play?.ref, let win = item.homeWinPercentage,
                  let id = ref.components(separatedBy: "/plays/").last?.components(separatedBy: "?").first
            else { return nil }
            return ProbabilityPoint(playID: id, homeWin: win, homeCover: item.spreadCoverProbHome, over: item.totalOverProb)
        }
    }

    public func gameDetail(for game: Game) async throws -> GameDetail {
        let path = try Self.path(for: game.leagueID)
        var detail = try Self.parseSummary(try await fetch(ESPNEndpoints.summary(path: path, gameID: game.id)), leagueID: game.leagueID)
        if [League.nba.id, League.wnba.id, League.nfl.id, League.cfb.id, League.nhl.id].contains(game.leagueID), game.status == .live {
            // Optional extra: the court still draws without timeouts and fouls.
            detail.court = try? Self.parseCourtSituation(try await fetch(ESPNEndpoints.situation(path: path, gameID: game.id)))
        }
        return detail
    }

    /// ESPN core API's competition situation: timeouts left, fouls this period and bonus, per team.
    /// Football gives timeouts left as a plain number. Basketball nests them in an object whose
    /// `timeoutsCurrent` counts timeouts used; the ones left are `timeoutsRemainingCurrent`.
    static func parseCourtSituation(_ data: Data) throws -> CourtSituation {
        struct DTO: Decodable {
            struct Timeouts: Decodable {
                let left: Int?
                init(from decoder: Decoder) throws {
                    if let count = try? decoder.singleValueContainer().decode(Int.self) {
                        left = count
                    } else {
                        enum Keys: CodingKey { case timeoutsRemainingCurrent }
                        left = try decoder.container(keyedBy: Keys.self).decodeIfPresent(Int.self, forKey: .timeoutsRemainingCurrent)
                    }
                }
            }
            struct Fouls: Decodable { let teamFoulsCurrent: Int?; let bonusState: String? }
            let awayTimeouts: Timeouts?, homeTimeouts: Timeouts?, awayFouls: Fouls?, homeFouls: Fouls?
            let powerPlay: Bool?, emptyNet: Bool?
        }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        func side(_ timeouts: DTO.Timeouts?, _ fouls: DTO.Fouls?) -> CourtSituation.Side {
            .init(timeoutsLeft: timeouts?.left, fouls: fouls?.teamFoulsCurrent,
                  inBonus: (fouls?.bonusState).map { $0 != "NONE" } ?? false)
        }
        return CourtSituation(away: side(dto.awayTimeouts, dto.awayFouls), home: side(dto.homeTimeouts, dto.homeFouls),
                              powerPlay: dto.powerPlay ?? false, emptyNet: dto.emptyNet ?? false)
    }

    private static func path(for leagueID: League.ID) throws -> String {
        guard let path = ESPNEndpoints.leaguePaths[leagueID] else { throw ESPNError.unsupportedLeague(leagueID) }
        return path
    }

    private func fetch(_ url: URL) async throws -> Data {
        try await fetch(URLRequest(url: url))
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ESPNError.badStatus(status) }
        return data
    }

    static func parseSummary(_ data: Data, leagueID: League.ID? = nil) throws -> GameDetail {
        let summary = try JSONDecoder().decode(SummaryDTO.self, from: data)
        var drives = summary.drives?.previous ?? []
        // The live drive also appears at the end of `previous`, possibly stale.
        if let current = summary.drives?.current {
            drives.removeAll { $0.id == current.id }
            drives.append(current)
        }
        // NFL groups plays into drives; most sports send a flat list; soccer only has key events.
        let plays: [Play]
        let modelDrives = drives.map { drive in
            Drive(id: drive.id, teamID: drive.team?.id, summary: drive.description ?? "",
                  result: drive.displayResult, isScore: drive.isScore ?? false,
                  plays: drive.plays.map { $0.play(teamID: drive.team?.id, league: leagueID) })
        }
        if !drives.isEmpty {
            plays = modelDrives.flatMap(\.plays)
        } else {
            // Some feeds leave scoringPlay empty, so fall back to the running score changing.
            var previous: (Int?, Int?) = (0, 0)
            var lastPitch: DrivesDTO.PlayDTO?
            plays = (summary.plays ?? summary.keyEvents ?? []).map { dto in
                var play = dto.play(teamID: nil, league: leagueID)
                defer { lastPitch = dto }
                // Baseball: a "Play Result" row's outcome ("Single", "Fly Out") is the type of the pitch put in play.
                if dto.type?.text == "Play Result", let pitch = lastPitch, pitch.text?.hasSuffix("In Play") == true {
                    play = play.headlined(pitch.type?.text)
                }
                // Strikeouts, walks and the like have no ball in play to name them, so read the result's own words.
                if dto.type?.text == "Play Result", play.headline == nil {
                    play = play.headlined(Play.baseballResult(play.text))
                }
                if dto.scoringPlay == nil, let away = dto.awayScore, let home = dto.homeScore {
                    play = play.scoring((away, home) != (previous.0 ?? 0, previous.1 ?? 0))
                    previous = (away, home)
                }
                return play
            }
        }

        var boxScores = (summary.boxscore?.players ?? []).flatMap { team in
            team.statistics.enumerated().compactMap { index, category -> BoxScore? in
                guard let labels = category.labels, !labels.isEmpty else { return nil }
                return BoxScore(teamID: team.team.id, category: category.name ?? "players-\(index)",
                                title: category.text ?? "\(team.team.displayName ?? "") \(category.name?.capitalized ?? "Players")",
                                labels: labels,
                                rows: (category.athletes ?? []).compactMap { row in
                                    row.stats.map { .init(id: row.athlete.id, name: row.athlete.displayName, stats: $0) }
                                })
            }
        }

        // Soccer has no player tables in the box score; the line-ups carry each player's stats instead.
        if boxScores.isEmpty, let rosters = summary.rosters {
            boxScores = rosters.compactMap(\.boxScore)
        }

        let teams = summary.boxscore?.teams ?? []
        var teamStats: [TeamStat] = []
        if let away = teams.first(where: { $0.homeAway == "away" }),
           let home = teams.first(where: { $0.homeAway == "home" }) {
            // Both teams list the same stats in the same order.
            teamStats = zip(away.flatStatistics, home.flatStatistics).enumerated().compactMap { index, pair in
                guard let label = pair.0.label ?? pair.0.displayName, let awayValue = pair.0.displayValue,
                      let homeValue = pair.1.displayValue else { return nil }
                return TeamStat(id: index, label: label, away: awayValue, home: homeValue)
            }
        }
        var detail = GameDetail(plays: plays, drives: modelDrives, boxScores: boxScores, teamStats: teamStats,
                                overview: summary.overview)
        // Commentary names teams but gives no IDs, so match them through the line-ups.
        let teamIDs = Dictionary((summary.rosters ?? []).compactMap { r in r.team.displayName.map { ($0, r.team.id) } },
                                 uniquingKeysWith: { first, _ in first })
        detail.shots = (summary.commentary ?? []).compactMap { $0.play?.shot(teamIDs: teamIDs) }
        detail.periodScores = Dictionary((summary.header?.competitions?.first?.competitors ?? []).map { competitor in
            (competitor.team.id, (competitor.linescores ?? []).compactMap { $0.displayValue.flatMap { Int($0) } })
        }, uniquingKeysWith: { first, _ in first })
        return detail
    }

    static func parseScoreboard(_ data: Data, leagueID: League.ID) throws -> [Game] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateStrategy
        let games = try decoder.decode(ScoreboardDTO.self, from: data).events.compactMap { $0.game(leagueID: leagueID) }
        // A dated college scoreboard is the full slate; the app only carries games with a Top 25 team.
        guard leagueID == League.cfb.id else { return games }
        return games.filter { $0.away.rank != nil || $0.home.rank != nil }
    }

    private static let dateStrategy = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let string = try decoder.singleValueContainer().decode(String.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // ESPN usually omits seconds ("2026-10-20T00:15Z"), which .iso8601 rejects.
        for format in ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                debugDescription: "Unrecognised date \(string)"))
    }
}

// MARK: - ESPN wire format (never leaves this file)

private struct ScoreboardDTO: Decodable {
    let events: [EventDTO]
}

private struct StandingsNodeDTO: Decodable {
    struct TableDTO: Decodable { let entries: [EntryDTO] }
    struct EntryDTO: Decodable {
        struct StatDTO: Decodable {
            let name: String
            let value: Double?
            let displayValue: String?
        }
        struct TeamDTO: Decodable {
            struct LogoDTO: Decodable { let href: URL? }
            let id: String
            let abbreviation: String
            let displayName: String
            let shortDisplayName: String
            let logos: [LogoDTO]?

            var team: Team {
                Team(id: id, abbreviation: abbreviation, displayName: displayName, shortName: shortDisplayName,
                     colorHex: nil, alternateColorHex: nil, logoURL: logos?.first?.href)
            }
        }
        let team: TeamDTO
        let stats: [StatDTO]

        func value(_ name: String) -> Double? { stats.first { $0.name == name }?.value }
        func display(_ name: String) -> String? { stats.first { $0.name == name }?.displayValue.flatMap { $0.isEmpty ? nil : $0 } }
    }

    let name: String?
    let children: [StandingsNodeDTO]?
    let standings: TableDTO?
}

/// Only what's needed to pick a game; scores come from the scoreboard.
private struct ScheduleDTO: Decodable {
    struct EventDTO: Decodable {
        struct CompetitionDTO: Decodable {
            struct StatusDTO: Decodable {
                struct TypeDTO: Decodable { let state: String }
                let type: TypeDTO
            }
            let status: StatusDTO
        }
        let id: String
        let date: Date
        let competitions: [CompetitionDTO]
    }
    let events: [EventDTO]
}

private struct EventDTO: Decodable {
    let id: String
    let date: Date
    let competitions: [CompetitionDTO]

    func game(leagueID: League.ID) -> Game? {
        guard let competition = competitions.first,
              let home = competition.competitors.first(where: { $0.homeAway == "home" }),
              let away = competition.competitors.first(where: { $0.homeAway == "away" })
        else { return nil }
        let status = competition.status.type.gameStatus
        return Game(
            id: id,
            leagueID: leagueID,
            startDate: date,
            status: status,
            period: competition.status.period,
            clock: competition.status.displayClock,
            statusDetail: competition.status.type.shortDetail,
            home: home.competitor(started: status != .scheduled),
            away: away.competitor(started: status != .scheduled),
            intermission: competition.status.type.intermission,
            situation: competition.situation.map { s in
                Game.Situation(possessionTeamID: s.possession, isRedZone: s.isRedZone ?? false,
                               downAndDistance: s.downDistanceText, yardLine: s.yardLine, distance: s.distance,
                               shortDownAndDistance: s.shortDownDistanceText.map { short in
                                   s.possessionText.map { "\(short) · \($0)" } ?? short
                               },
                               baseball: s.balls.map { balls in
                                   Game.Situation.Baseball(balls: balls, strikes: s.strikes ?? 0, outs: s.outs ?? 0,
                                                           onFirst: s.onFirst ?? false, onSecond: s.onSecond ?? false,
                                                           onThird: s.onThird ?? false,
                                                           batter: s.batter?.athlete?.shortName ?? s.batter?.athlete?.displayName,
                                                           pitcher: s.pitcher?.athlete?.shortName ?? s.pitcher?.athlete?.displayName)
                               })
            },
            note: competition.notes?.first?.headline,
            seriesSummary: competition.series?.summary,
            broadcasts: competition.watchOn
        )
    }
}

private struct CompetitionDTO: Decodable {
    struct SituationDTO: Decodable {
        let possession: String?
        let isRedZone: Bool?
        let downDistanceText: String?
        let shortDownDistanceText: String?
        let possessionText: String?
        let yardLine: Int?
        let distance: Int?
        let balls: Int?
        let strikes: Int?
        let outs: Int?
        let onFirst: Bool?
        let onSecond: Bool?
        let onThird: Bool?
        let batter: PersonDTO?
        let pitcher: PersonDTO?

        struct PersonDTO: Decodable {
            struct AthleteDTO: Decodable { let displayName: String?; let shortName: String? }
            let athlete: AthleteDTO?
        }
    }

    struct NoteDTO: Decodable { let headline: String? }
    struct SeriesDTO: Decodable { let summary: String? }

    let notes: [NoteDTO]?
    let series: SeriesDTO?
    let broadcasts: [BroadcastNamesDTO]?
    let geoBroadcasts: [GeoBroadcastDTO]?

    struct BroadcastNamesDTO: Decodable { let market: String?; let names: [String]? }
    struct GeoBroadcastDTO: Decodable {
        struct Media: Decodable { let shortName: String? }
        struct Market: Decodable { let type: String? }
        let media: Media?
        let market: Market?
    }

    /// Channels and streaming apps, national before local, without repeats.
    var watchOn: [String] {
        let geo = (geoBroadcasts ?? []).sorted { ($0.market?.type == "National" ? 0 : 1) < ($1.market?.type == "National" ? 0 : 1) }
            .compactMap(\.media?.shortName)
        let names = geo.isEmpty
            ? (broadcasts ?? []).sorted { ($0.market == "national" ? 0 : 1) < ($1.market == "national" ? 0 : 1) }.flatMap { $0.names ?? [] }
            : geo
        return names.reduce(into: []) { if !$1.isEmpty && !$0.contains($1) { $0.append($1) } }
    }

    let status: StatusDTO
    let competitors: [CompetitorDTO]
    let situation: SituationDTO?
}

private struct StatusDTO: Decodable {
    struct TypeDTO: Decodable {
        let name: String?
        let state: String
        let shortDetail: String

        var intermission: Game.Intermission? {
            switch name {
            case "STATUS_HALFTIME": .halftime
            case "STATUS_END_PERIOD": .endOfPeriod
            default: nil
            }
        }

        // shortcut: postponed/cancelled games arrive as "post" and show as final with their detail text; add a status when the UI needs it.
        var gameStatus: Game.Status {
            switch state {
            case "in": .live
            case "post": .final
            default: .scheduled
            }
        }
    }

    let displayClock: String
    let period: Int
    let type: TypeDTO
}

private struct CompetitorDTO: Decodable {
    struct LineScoreDTO: Decodable {
        let value: Double
    }

    struct RecordDTO: Decodable {
        let summary: String?
    }

    let homeAway: String
    let score: String?
    let linescores: [LineScoreDTO]?
    let records: [RecordDTO]?
    let team: TeamDTO
    /// College poll rank; ESPN sends 99 for unranked teams.
    let curatedRank: RankDTO?

    struct RankDTO: Decodable { let current: Int? }

    func competitor(started: Bool) -> Game.Competitor {
        Game.Competitor(
            team: team.team,
            score: started ? score.flatMap { Int($0) } : nil,
            periodScores: (linescores ?? []).map { Int($0.value) },
            // ESPN lists the overall record first.
            record: records?.first?.summary,
            rank: curatedRank?.current.flatMap { (1...25).contains($0) ? $0 : nil }
        )
    }
}

private struct TeamDTO: Decodable {
    let id: String
    let abbreviation: String
    let displayName: String
    let shortDisplayName: String
    let color: String?
    let alternateColor: String?
    let logo: URL?

    var team: Team {
        Team(id: id, abbreviation: abbreviation, displayName: displayName, shortName: shortDisplayName,
             colorHex: color, alternateColorHex: alternateColor, logoURL: logo)
    }
}

private struct RankingsDTO: Decodable {
    struct PollDTO: Decodable {
        struct RankDTO: Decodable {
            struct TeamDTO: Decodable {
                struct LogoDTO: Decodable { let href: URL? }
                let id: String
                let location: String
                let name: String?
                let abbreviation: String
                let color: String?
                let logos: [LogoDTO]?

                var team: Team {
                    Team(id: id, abbreviation: abbreviation, displayName: [location, name].compactMap { $0 }.joined(separator: " "),
                         shortName: location, colorHex: color, alternateColorHex: nil, logoURL: logos?.first?.href)
                }
            }

            let team: TeamDTO
            let recordSummary: String?
            let points: Double?
        }

        let name: String?
        let type: String?
        let ranks: [RankDTO]
    }

    let rankings: [PollDTO]
}

private struct TeamRefDTO: Decodable {
    let id: String
    let displayName: String?
}

private struct SummaryDTO: Decodable {
    let boxscore: BoxscoreDTO?
    let rosters: [RosterDTO]?
    let commentary: [CommentaryDTO]?
    let drives: DrivesDTO?
    let plays: [DrivesDTO.PlayDTO]?
    let keyEvents: [DrivesDTO.PlayDTO]?
    let gameInfo: GameInfoDTO?
    let pickcenter: [OddsDTO]?
    let odds: [OddsDTO]?
    let header: HeaderDTO?
    let predictor: PredictorDTO?
    let standings: SummaryStandingsDTO?
    let leaders: [TeamLeadersDTO]?
    let article: ArticleDTO?

    struct ArticleDTO: Decodable {
        struct Links: Decodable { struct Link: Decodable { let href: URL? }; let web: Link? }
        let headline: String?
        let story: String?
        let links: Links?

        /// The story's HTML as plain paragraphs: tags dropped, common entities decoded, blank lines removed.
        var recap: GameOverview.Recap? {
            guard let headline, let story, !story.isEmpty else { return nil }
            let text = story
                .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
                .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">",
                            "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&mdash;": "\u{2014}"]
            let decoded = entities.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
            // ESPN's datelines read "ORLANDO, Fla. -- — Nickeil…"; keep one dash.
            let paragraphs = decoded.replacingOccurrences(of: "-- \u{2014}", with: "\u{2014}").components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return paragraphs.isEmpty ? nil : .init(headline: headline, paragraphs: paragraphs, url: links?.web?.href)
        }
    }

    struct GameInfoDTO: Decodable {
        struct VenueDTO: Decodable {
            struct AddressDTO: Decodable { let city: String?; let state: String?; let country: String? }
            struct ImageDTO: Decodable { let href: URL? }
            let fullName: String?
            let address: AddressDTO?
            let images: [ImageDTO]?
        }
        let venue: VenueDTO?
        let attendance: Int?
    }

    struct OddsDTO: Decodable {
        struct ProviderDTO: Decodable { let name: String? }
        struct SideDTO: Decodable { let moneyLine: Int? }
        let provider: ProviderDTO?
        let spread: Double?
        let overUnder: Double?
        let homeTeamOdds: SideDTO?
        let awayTeamOdds: SideDTO?
    }

    struct HeaderDTO: Decodable {
        struct CompetitionDTO: Decodable {
            struct BroadcastDTO: Decodable {
                struct MediaDTO: Decodable { let shortName: String? }
                let media: MediaDTO?
            }
            struct CompetitorDTO: Decodable {
                struct TeamDTO: Decodable { let id: String }
                struct LineScoreDTO: Decodable { let displayValue: String? }
                let team: TeamDTO
                let linescores: [LineScoreDTO]?
            }
            let broadcasts: [BroadcastDTO]?
            let competitors: [CompetitorDTO]?
        }
        let competitions: [CompetitionDTO]?
    }

    struct PredictorDTO: Decodable {
        struct SideDTO: Decodable { let id: String?; let gameProjection: String? }
        let homeTeam: SideDTO?
        let awayTeam: SideDTO?
    }

    struct SummaryStandingsDTO: Decodable {
        struct GroupDTO: Decodable {
            struct TableDTO: Decodable {
                struct EntryDTO: Decodable {
                    struct StatDTO: Decodable { let name: String; let displayValue: String? }
                    let id: String?
                    let stats: [StatDTO]?
                }
                let entries: [EntryDTO]
            }
            let header: String?
            let standings: TableDTO?
        }
        let groups: [GroupDTO]?
    }

    struct TeamLeadersDTO: Decodable {
        struct CategoryDTO: Decodable {
            struct LeaderDTO: Decodable {
                struct AthleteDTO: Decodable {
                    struct HeadshotDTO: Decodable { let href: URL? }
                    struct PositionDTO: Decodable { let abbreviation: String? }
                    let displayName: String?
                    let shortName: String?
                    let headshot: HeadshotDTO?
                    let position: PositionDTO?
                }
                struct MainStatDTO: Decodable { let value: String? }
                let displayValue: String?
                let athlete: AthleteDTO?
                let mainStat: MainStatDTO?
                let summary: String?
            }
            let displayName: String?
            let leaders: [LeaderDTO]?
        }
        let team: TeamRefDTO?
        let leaders: [CategoryDTO]?
    }

    var overview: GameOverview {
        let venue = gameInfo?.venue.flatMap { v in
            v.fullName.map {
                GameOverview.Venue(name: $0, city: v.address?.city, region: v.address?.state,
                                   country: v.address?.country, imageURL: v.images?.first?.href)
            }
        }
        // Average every listed sportsbook; ESPN's free feed often has just one.
        let books = (pickcenter ?? []) + (odds ?? [])
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let odds = books.isEmpty ? nil : GameOverview.Odds(
            books: Array(Set(books.compactMap { $0.provider?.name })).sorted(),
            homeSpread: average(books.compactMap(\.spread)),
            overUnder: average(books.compactMap(\.overUnder)),
            homeMoneyLine: average(books.compactMap { $0.homeTeamOdds?.moneyLine.map(Double.init) }).map { Int($0.rounded()) },
            awayMoneyLine: average(books.compactMap { $0.awayTeamOdds?.moneyLine.map(Double.init) }).map { Int($0.rounded()) })
        let standings = (self.standings?.groups ?? []).flatMap { group -> [GameOverview.Standing] in
            // "2026 NFC West Standings" → "NFC West"
            let name = (group.header ?? "").replacingOccurrences(of: "Standings", with: "")
                .split(separator: " ").filter { Int($0) == nil }.joined(separator: " ")
            return (group.standings?.entries ?? []).enumerated().compactMap { index, entry in
                entry.id.map {
                    GameOverview.Standing(teamID: $0, group: name, position: index + 1,
                                          record: entry.stats?.first { $0.name == "overall" }?.displayValue)
                }
            }
        }
        var probability: [Team.ID: Double] = [:]
        for side in [predictor?.homeTeam, predictor?.awayTeam].compactMap({ $0 }) {
            if let id = side.id, let value = side.gameProjection.flatMap(Double.init) { probability[id] = value }
        }
        let leaders = (self.leaders ?? []).flatMap { team in
            (team.leaders ?? []).compactMap { category -> GameOverview.Leader? in
                guard let id = team.team?.id, let top = category.leaders?.first,
                      let name = top.athlete?.displayName, let line = top.displayValue else { return nil }
                return GameOverview.Leader(teamID: id, category: category.displayName ?? "", athlete: name, line: line,
                                           shortName: top.athlete?.shortName, position: top.athlete?.position?.abbreviation,
                                           headshotURL: top.athlete?.headshot?.href, mainValue: top.mainStat?.value,
                                           summary: top.summary)
            }
        }
        return GameOverview(
            venue: venue, attendance: gameInfo?.attendance.flatMap { $0 > 0 ? $0 : nil },
            broadcasts: Array(NSOrderedSet(array: (header?.competitions?.first?.broadcasts ?? []).compactMap { $0.media?.shortName }))
                .compactMap { $0 as? String },
            odds: odds, standings: standings, winProbability: probability, leaders: leaders, recap: article?.recap)
    }
}

private struct BoxscoreDTO: Decodable {
    struct TeamStatsDTO: Decodable {
        struct StatDTO: Decodable {
            let name: String?
            let label: String?
            let displayName: String?
            let displayValue: String?
            /// MLB nests its stats in batting, pitching and fielding groups.
            let stats: [StatDTO]?
        }

        /// The few of MLB's 170 grouped stats that a box score shows, in display order.
        static let mlbStats = [
            "batting": ["hits", "runs", "homeRuns", "RBIs", "walks", "strikeouts", "runnersLeftOnBase", "avg"],
            "pitching": ["pitches", "strikes", "earnedRuns"],
            "fielding": ["errors", "doublePlays"],
        ]

        let homeAway: String
        let statistics: [StatDTO]

        var flatStatistics: [StatDTO] {
            statistics.flatMap { group -> [StatDTO] in
                guard let stats = group.stats else { return [group] }
                return (Self.mlbStats[group.name ?? ""] ?? []).compactMap { name in stats.first { $0.name == name } }
            }
        }
    }

    struct PlayersDTO: Decodable {
        struct CategoryDTO: Decodable {
            struct AthleteRowDTO: Decodable {
                struct AthleteDTO: Decodable {
                    let id: String
                    let displayName: String
                }

                let athlete: AthleteDTO
                let stats: [String]?
            }

            let name: String?
            let text: String?
            let labels: [String]?
            let athletes: [AthleteRowDTO]?
        }

        let team: TeamRefDTO
        let statistics: [CategoryDTO]
    }

    let teams: [TeamStatsDTO]?
    let players: [PlayersDTO]?
}

/// A line of soccer match commentary; shots carry where they were taken from.
private struct CommentaryDTO: Decodable {
    struct PlayDTO: Decodable {
        struct TypeDTO: Decodable { let type: String? }
        struct TeamDTO: Decodable { let displayName: String? }
        struct ClockDTO: Decodable { let displayValue: String? }
        struct PeriodDTO: Decodable { let number: Int? }
        struct ParticipantDTO: Decodable { struct Athlete: Decodable { let displayName: String? }; let athlete: Athlete? }

        let id: String
        let type: TypeDTO?
        let team: TeamDTO?
        let shortText: String?
        let clock: ClockDTO?
        let period: PeriodDTO?
        /// The shooter first, then any assister.
        let participants: [ParticipantDTO]?
        let fieldPositionX: Double?
        let fieldPositionY: Double?
        let fieldPosition2X: Double?
        let fieldPosition2Y: Double?

        /// nil for anything that isn't an attempt on goal (own goals included) or has no spot.
        func shot(teamIDs: [String: Team.ID]) -> Shot? {
            let kind = type?.type ?? ""
            let outcome: Shot.Outcome? = switch kind {
            case _ where kind.hasPrefix("goal"), "penalty---scored": .goal
            case "shot-on-target", "penalty---saved": .save
            case "shot-off-target", "penalty---missed": .offTarget
            case "shot-blocked": .block
            default: nil
            }
            guard let outcome, let x = fieldPositionX, let y = fieldPositionY,
                  let name = team?.displayName, let teamID = teamIDs[name] else { return nil }
            return Shot(id: id, teamID: teamID, outcome: outcome, location: .init(x: x / 100, y: y / 100),
                        text: [shortText, clock?.displayValue].compactMap { $0 }.joined(separator: " · "),
                        period: period?.number ?? 1, shooter: participants?.first?.athlete?.displayName,
                        end: fieldPosition2X.flatMap { ex in fieldPosition2Y.map { .init(x: ex / 100, y: $0 / 100) } })
        }
    }

    let play: PlayDTO?
}

/// A soccer line-up, with each player's match stats.
private struct RosterDTO: Decodable {
    struct PlayerDTO: Decodable {
        struct AthleteDTO: Decodable { let id: String; let displayName: String }
        struct PositionDTO: Decodable { let abbreviation: String? }
        struct StatDTO: Decodable { let abbreviation: String?; let displayValue: String? }

        let starter: Bool?
        let subbedIn: Bool?
        let athlete: AthleteDTO
        let position: PositionDTO?
        let stats: [StatDTO]?
    }

    struct TeamDTO: Decodable { let id: String; let displayName: String? }

    /// ESPN's stat abbreviations, and the labels shown for them (ESPN's website style).
    static let columns = [("G", "G"), ("A", "A"), ("SHOT", "SH"), ("SOG", "ST"), ("FC", "FC"), ("FA", "FA"), ("YC", "YC"), ("RC", "RC")]

    let team: TeamDTO
    let roster: [PlayerDTO]?

    /// Starters, then the subs who came on; unused subs are left out.
    var boxScore: BoxScore? {
        let played = (roster ?? []).filter { $0.starter == true } + (roster ?? []).filter { $0.starter != true && $0.subbedIn == true }
        guard !played.isEmpty else { return nil }
        return BoxScore(teamID: team.id, category: "players", title: "\(team.displayName ?? "") Players",
                        labels: ["POS"] + Self.columns.map(\.1),
                        rows: played.map { player in
                            let stats = Dictionary((player.stats ?? []).compactMap { s in s.abbreviation.map { ($0, s.displayValue ?? "") } },
                                                   uniquingKeysWith: { first, _ in first })
                            return .init(id: player.athlete.id, name: player.athlete.displayName,
                                         stats: [player.position?.abbreviation ?? ""] + Self.columns.map { stats[$0.0] ?? "0" })
                        },
                        key: "SH shots · ST on target · FC fouls committed · FA fouls won · YC/RC yellow/red cards")
    }
}

private struct DrivesDTO: Decodable {
    struct DriveDTO: Decodable {
        let id: String
        let team: TeamRefDTO?
        let description: String?
        let displayResult: String?
        let isScore: Bool?
        let plays: [PlayDTO]
    }

    struct PlayDTO: Decodable {
        struct PeriodDTO: Decodable { let number: Int }
        struct ClockDTO: Decodable { let displayValue: String }

        let id: String
        let text: String?
        let period: PeriodDTO?
        let clock: ClockDTO?
        let scoringPlay: Bool?
        let awayScore: Int?
        let homeScore: Int?
        let team: TeamRefDTO?
        let type: TypeDTO?
        let start: SpotDTO?
        let end: SpotDTO?
        let coordinate: PointDTO?
        let hitCoordinate: PointDTO?
        let fieldPositionX: Double?
        let fieldPositionY: Double?
        let shootingPlay: Bool?
        let shortDescription: String?

        struct PointDTO: Decodable { let x: Double?; let y: Double? }

        /// Normalises the league's coordinates to 0–1 of its surface (see `Play.Location`).
        /// ESPN marks plays without a spot with huge negative sentinels, which fall outside these ranges.
        func location(league: League.ID?) -> Play.Location? {
            switch league {
            case League.epl.id, League.ucl.id, League.mls.id:                         // 0–100 toward goal
                guard let x = fieldPositionX, let y = fieldPositionY else { return nil }
                return .init(x: x / 100, y: y / 100)
            case League.mlb.id:                                                       // 250-unit hit chart
                guard let x = hitCoordinate?.x, let y = hitCoordinate?.y, (0...250).contains(x), (0...250).contains(y) else { return nil }
                return .init(x: x / 250, y: y / 250)
            case League.nhl.id:                                                       // feet from centre ice
                guard let x = coordinate?.x, let y = coordinate?.y, (-100...100).contains(x), (-42.5...42.5).contains(y) else { return nil }
                return .init(x: (x + 100) / 200, y: (42.5 - y) / 85)
            case League.nba.id, League.wnba.id:                                       // feet, half court
                guard let x = coordinate?.x, let y = coordinate?.y, (0...50).contains(x), (0...47).contains(y) else { return nil }
                return .init(x: x / 50, y: y / 47)
            default:
                return nil
            }
        }
        struct TypeDTO: Decodable { let text: String? }
        struct SpotDTO: Decodable {
            let yardLine: Int?
            let downDistanceText: String?
        }

        /// College football wraps plays as "(09:07) … , End Of Play"; the clock is shown on its own, so both go.
        private var cleanText: String {
            (text ?? "")
                .replacingOccurrences(of: #"^\(\d{1,2}:\d{2}\)\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #",?\s*End Of Play\.?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        }

        func play(teamID: Team.ID?, league: League.ID? = nil) -> Play {
            // College overtime is untimed; ESPN stamps every snap 0:00, which reads as a clock that stopped.
            let untimed = league == League.cfb.id && (period?.number ?? 0) > League.cfb.regulationPeriods
            return Play(id: id, text: cleanText, period: period?.number ?? 0, clock: untimed ? "" : clock?.displayValue ?? "",
                 teamID: teamID ?? team?.id, isScoring: scoringPlay ?? false, awayScore: awayScore, homeScore: homeScore,
                 type: type?.text, spot: start?.downDistanceText, startYardLine: start?.yardLine, endYardLine: end?.yardLine,
                 location: location(league: league), isShot: shootingPlay ?? (hitCoordinate != nil), headline: shortDescription)
        }
    }

    let previous: [DriveDTO]?
    let current: DriveDTO?
}
