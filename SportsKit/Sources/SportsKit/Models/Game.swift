import Foundation

public struct Game: Identifiable, Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case scheduled, live, final
    }

    /// A break in a live game.
    public enum Intermission: Hashable, Sendable {
        case endOfPeriod, halftime
    }

    /// Ball state for sports with possession (NFL).
    public struct Situation: Hashable, Sendable {
        public let possessionTeamID: Team.ID?
        public let isRedZone: Bool
        /// e.g. "1st & 10 at BUF 18".
        public let downAndDistance: String?
        /// Ball position in yards from the home team's goal line (0–100).
        public let yardLine: Int?
        /// Yards to a first down.
        public let distance: Int?
        /// Short form for score rows, e.g. "1st & 10 · BUF 18".
        public let shortDownAndDistance: String?
        /// Baseball: the count, outs and runners.
        public let baseball: Baseball?

        public struct Baseball: Hashable, Sendable {
            public let balls: Int
            public let strikes: Int
            public let outs: Int
            public let onFirst: Bool
            public let onSecond: Bool
            public let onThird: Bool
            public let batter: String?
            public let pitcher: String?

            public init(balls: Int, strikes: Int, outs: Int, onFirst: Bool, onSecond: Bool, onThird: Bool,
                        batter: String?, pitcher: String?) {
                self.balls = balls
                self.strikes = strikes
                self.outs = outs
                self.onFirst = onFirst
                self.onSecond = onSecond
                self.onThird = onThird
                self.batter = batter
                self.pitcher = pitcher
            }
        }

        public init(possessionTeamID: Team.ID?, isRedZone: Bool, downAndDistance: String?,
                    yardLine: Int? = nil, distance: Int? = nil, shortDownAndDistance: String? = nil,
                    baseball: Baseball? = nil) {
            self.possessionTeamID = possessionTeamID
            self.isRedZone = isRedZone
            self.downAndDistance = downAndDistance
            self.yardLine = yardLine
            self.distance = distance
            self.shortDownAndDistance = shortDownAndDistance
            self.baseball = baseball
        }
    }

    public struct Competitor: Hashable, Sendable {
        public let team: Team
        /// nil before the game starts.
        public let score: Int?
        /// Points per period, in order (overtime periods included).
        public let periodScores: [Int]
        /// Season record as the provider writes it, e.g. "5-2" or "7-3-1".
        public let record: String?

        public init(team: Team, score: Int?, periodScores: [Int], record: String? = nil) {
            self.team = team
            self.score = score
            self.periodScores = periodScores
            self.record = record
        }
    }

    public let id: String
    public let leagueID: League.ID
    public let startDate: Date
    public let status: Status
    public let period: Int
    /// Display clock, e.g. "6:26".
    public let clock: String
    /// Provider's short status text, e.g. "6:26 - 2nd" or "Final/OT".
    public let statusDetail: String
    public let home: Competitor
    public let away: Competitor
    public let intermission: Intermission?
    public let situation: Situation?
    /// Event note, e.g. "ALCS - Game 6".
    public let note: String?
    /// Playoff series state, e.g. "TB leads series 3-2".
    public let seriesSummary: String?
    /// Where to watch, national first, e.g. ["ESPN", "Prime Video"].
    public let broadcasts: [String]

    public init(id: String, leagueID: League.ID, startDate: Date, status: Status, period: Int,
                clock: String, statusDetail: String, home: Competitor, away: Competitor,
                intermission: Intermission? = nil, situation: Situation? = nil,
                note: String? = nil, seriesSummary: String? = nil, broadcasts: [String] = []) {
        self.id = id
        self.leagueID = leagueID
        self.startDate = startDate
        self.status = status
        self.period = period
        self.clock = clock
        self.statusDetail = statusDetail
        self.home = home
        self.away = away
        self.intermission = intermission
        self.situation = situation
        self.note = note
        self.seriesSummary = seriesSummary
        self.broadcasts = broadcasts
    }
}
