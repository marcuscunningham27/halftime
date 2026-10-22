import Foundation

/// Every unofficial ESPN path lives here, so breakage is fixed in one place.
enum ESPNEndpoints {
    static let base = URL(string: "https://site.api.espn.com/apis/site/v2/sports/")!

    /// League ID → ESPN "sport/league" path. Adding a league means adding a row.
    static let leaguePaths: [League.ID: String] = [
        League.nfl.id: "football/nfl",
        League.nba.id: "basketball/nba",
        League.wnba.id: "basketball/wnba",
        League.mlb.id: "baseball/mlb",
        League.nhl.id: "hockey/nhl",
        League.epl.id: "soccer/eng.1",
    ]

    /// nil asks for ESPN's "current" slate: this week for NFL, the latest round for off-season leagues.
    static func scoreboard(path: String, espnDay: String?) -> URL {
        let url = base.appending(path: path).appending(path: "scoreboard")
        return espnDay.map { url.appending(queryItems: [URLQueryItem(name: "dates", value: $0)]) } ?? url
    }

    /// One NFL regular-season week (seasontype 2).
    static func nflWeek(season: String, week: Int) -> URL {
        base.appending(path: "football/nfl/scoreboard").appending(queryItems: [
            URLQueryItem(name: "dates", value: season), URLQueryItem(name: "seasontype", value: "2"),
            URLQueryItem(name: "week", value: String(week)), URLQueryItem(name: "limit", value: "100"),
        ])
    }

    /// Standings live under /apis/v2, not the site API. `level` 3 splits conferences into divisions.
    static func standings(path: String, level: Int?) -> URL {
        let url = URL(string: "https://site.api.espn.com/apis/v2/sports/")!.appending(path: path).appending(path: "standings")
        return level.map { url.appending(queryItems: [URLQueryItem(name: "level", value: String($0))]) } ?? url
    }

    /// Which ESPN stats each league's table shows, how it's ranked, and whether to split by division.
    struct StandingsSpec {
        let level: Int?
        let columns: [(stat: String, label: String)]
        /// Higher is better, compared in order.
        let rankBy: [String]
    }

    static let standingsSpecs: [League.ID: StandingsSpec] = [
        League.nfl.id: .init(level: 3, columns: [("wins", "W"), ("losses", "L"), ("ties", "T"), ("winPercent", "PCT")],
                             rankBy: ["winPercent", "wins"]),
        League.nba.id: .init(level: nil, columns: [("wins", "W"), ("losses", "L"), ("winPercent", "PCT"), ("gamesBehind", "GB")],
                             rankBy: ["winPercent", "wins"]),
        League.wnba.id: .init(level: nil, columns: [("wins", "W"), ("losses", "L"), ("winPercent", "PCT"), ("gamesBehind", "GB")],
                              rankBy: ["winPercent", "wins"]),
        League.mlb.id: .init(level: 3, columns: [("wins", "W"), ("losses", "L"), ("winPercent", "PCT"), ("gamesBehind", "GB")],
                             rankBy: ["winPercent", "wins"]),
        League.nhl.id: .init(level: 3, columns: [("gamesPlayed", "GP"), ("wins", "W"), ("losses", "L"), ("otLosses", "OTL"), ("points", "PTS")],
                             rankBy: ["points", "wins"]),
        League.epl.id: .init(level: nil, columns: [("gamesPlayed", "GP"), ("wins", "W"), ("ties", "D"), ("losses", "L"),
                                                    ("pointDifferential", "GD"), ("points", "PTS")],
                             rankBy: ["points", "pointDifferential", "pointsFor"]),
    ]

    /// ESPN's core API, where "football/nfl" is written "football/leagues/nfl".
    static func probabilities(path: String, gameID: Game.ID) -> URL {
        let parts = path.split(separator: "/")
        return URL(string: "https://sports.core.api.espn.com/v2/sports/\(parts[0])/leagues/\(parts[1])/events/\(gameID)/competitions/\(gameID)/probabilities?limit=1000")!
    }

    static func situation(path: String, gameID: Game.ID) -> URL {
        let parts = path.split(separator: "/")
        return URL(string: "https://sports.core.api.espn.com/v2/sports/\(parts[0])/leagues/\(parts[1])/events/\(gameID)/competitions/\(gameID)/situation")!
    }

    static func schedule(path: String, teamID: Team.ID) -> URL {
        base.appending(path: path).appending(path: "teams").appending(path: teamID).appending(path: "schedule")
    }

    static func summary(path: String, gameID: Game.ID) -> URL {
        base.appending(path: path)
            .appending(path: "summary")
            .appending(queryItems: [URLQueryItem(name: "event", value: gameID)])
    }

    /// ESPN buckets games by US Eastern calendar day, so a local day can straddle two ESPN days.
    /// Fetching both and filtering by start time also covers leagues bucketed by their own local day.
    static func espnDays(covering day: DateInterval) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let days = [day.start, day.end.addingTimeInterval(-1)].map { date in
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
        }
        return days[0] == days[1] ? [days[0]] : days
    }
}
