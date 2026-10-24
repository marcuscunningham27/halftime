/// Everything shown below a game's header. The header itself comes from the scoreboard `Game`,
/// so there is one source of truth for score and clock.
public struct GameDetail: Hashable, Sendable {
    /// Plays in chronological order.
    public let plays: [Play]
    /// The same plays grouped into possessions, oldest first; empty for sports without drives.
    public let drives: [Drive]
    public let boxScores: [BoxScore]
    public let teamStats: [TeamStat]
    public let overview: GameOverview
    /// Timeouts, fouls and bonus for each team (NBA only, filled in while live).
    public var court: CourtSituation?
    /// Every located shot, for the soccer shot map (from ESPN's match commentary).
    public var shots: [Shot] = []
    /// Each team's score by period, from the summary; fills the line score where the scoreboard omits it (soccer).
    public var periodScores: [Team.ID: [Int]] = [:]

    public init(plays: [Play], drives: [Drive] = [], boxScores: [BoxScore], teamStats: [TeamStat],
                overview: GameOverview = GameOverview()) {
        self.plays = plays
        self.drives = drives
        self.boxScores = boxScores
        self.teamStats = teamStats
        self.overview = overview
    }
}

/// One attempt on goal and where it was taken from.
public struct Shot: Identifiable, Hashable, Sendable {
    public enum Outcome: String, CaseIterable, Sendable {
        case goal, save, offTarget, block
    }

    public let id: String
    public let teamID: Team.ID
    public let outcome: Outcome
    /// 0–1 of the pitch, in the shooting team's frame: x toward the goal it attacks, y across.
    public let location: Play.Location
    /// e.g. "Brandon Thomas-Asante Shot Block · 8'"
    public let text: String
    /// 1 or 2 for the halves; higher in extra time.
    public let period: Int
    public let shooter: String?
    /// Where the ball ended up, same frame as `location`; for goals, the spot it crossed the line.
    public let end: Play.Location?

    public init(id: String, teamID: Team.ID, outcome: Outcome, location: Play.Location, text: String,
                period: Int = 1, shooter: String? = nil, end: Play.Location? = nil) {
        self.id = id
        self.teamID = teamID
        self.outcome = outcome
        self.location = location
        self.text = text
        self.period = period
        self.shooter = shooter
        self.end = end
    }
}

public struct Drive: Identifiable, Hashable, Sendable {
    public let id: String
    public let teamID: Team.ID?
    /// e.g. "13 plays, 61 yards, 5:46"
    public let summary: String
    /// e.g. "Touchdown", "Punt"; nil while the drive is still going.
    public let result: String?
    public let isScore: Bool
    public let plays: [Play]

    public init(id: String, teamID: Team.ID?, summary: String, result: String?, isScore: Bool, plays: [Play]) {
        self.id = id
        self.teamID = teamID
        self.summary = summary
        self.result = result
        self.isScore = isScore
        self.plays = plays
    }
}

public struct Play: Identifiable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let period: Int
    public let clock: String
    /// Team with possession, when the sport has one.
    public let teamID: Team.ID?
    public let isScoring: Bool
    /// nil where the provider doesn't attach the running score (soccer key events).
    public let awayScore: Int?
    public let homeScore: Int?
    /// Short headline, e.g. "Incomplete Pass".
    public let type: String?
    /// Down, distance and spot before the snap, e.g. "4th & 3 at SF 17".
    public let spot: String?
    /// Ball position before the snap, in yards from the home goal line.
    public let startYardLine: Int?
    /// Ball position after the play, same measure.
    public let endYardLine: Int?
    /// Where it happened on the playing surface, as fractions (0–1) of it; see `Location`.
    public let location: Location?
    /// A shot or batted ball (as opposed to a foul, hit, timeout…).
    public let isShot: Bool
    /// ESPN's short summary, e.g. "+3 Points", "Rebound", "Missed FG".
    public let headline: String?

    /// A spot on the playing surface, each axis 0–1:
    /// basketball — x across the court, y out from the shooting team's baseline over half its length;
    /// hockey — x along the rink from the left end, y across it from the top;
    /// baseball — ESPN's square hit chart, home plate near (0.5, 0.82);
    /// soccer — x toward the goal the team attacks, y across the pitch.
    public struct Location: Hashable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public init(id: String, text: String, period: Int, clock: String, teamID: Team.ID?,
                isScoring: Bool, awayScore: Int?, homeScore: Int?,
                type: String? = nil, spot: String? = nil, startYardLine: Int? = nil, endYardLine: Int? = nil,
                location: Location? = nil, isShot: Bool = false, headline: String? = nil) {
        self.id = id
        self.text = text
        self.period = period
        self.clock = clock
        self.teamID = teamID
        self.isScoring = isScoring
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.type = type
        self.spot = spot
        self.startYardLine = startYardLine
        self.endYardLine = endYardLine
        self.location = location
        self.isShot = isShot
        self.headline = headline
    }

    func headlined(_ headline: String?) -> Play {
        Play(id: id, text: text, period: period, clock: clock, teamID: teamID, isScoring: isScoring,
             awayScore: awayScore, homeScore: homeScore, type: type, spot: spot,
             startYardLine: startYardLine, endYardLine: endYardLine, location: location, isShot: isShot, headline: headline)
    }

    func scoring(_ isScoring: Bool) -> Play {
        Play(id: id, text: text, period: period, clock: clock, teamID: teamID, isScoring: isScoring,
             awayScore: awayScore, homeScore: homeScore, type: type, spot: spot,
             startYardLine: startYardLine, endYardLine: endYardLine, location: location, isShot: isShot, headline: headline)
    }
}

/// One player stat table for one team, e.g. Chiefs passing.
public struct BoxScore: Identifiable, Hashable, Sendable {
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        /// Same order as `BoxScore.labels`.
        public let stats: [String]

        public init(id: String, name: String, stats: [String]) {
            self.id = id
            self.name = name
            self.stats = stats
        }
    }

    public var id: String { "\(teamID)-\(category)" }
    public let teamID: Team.ID
    /// Stable key, e.g. "passing".
    public let category: String
    /// Display title, e.g. "Kansas City Passing".
    public let title: String
    public let labels: [String]
    public let rows: [Row]
    /// What the column labels mean, where they aren't obvious (soccer).
    public var key: String?

    public init(teamID: Team.ID, category: String, title: String, labels: [String], rows: [Row], key: String? = nil) {
        self.teamID = teamID
        self.category = category
        self.title = title
        self.labels = labels
        self.rows = rows
        self.key = key
    }
}

public struct TeamStat: Identifiable, Hashable, Sendable {
    /// Position in the provider's list; names can repeat (ESPN lists interceptions twice).
    public let id: Int
    public let label: String
    public let away: String
    public let home: String

    public init(id: Int, label: String, away: String, home: String) {
        self.id = id
        self.label = label
        self.away = away
        self.home = home
    }
}
