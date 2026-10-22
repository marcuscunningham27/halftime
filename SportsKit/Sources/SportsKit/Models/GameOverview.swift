import Foundation

/// Pre-game and context information for a game: where, on what channel, the betting line, standings.
public struct GameOverview: Hashable, Sendable {
    public struct Venue: Hashable, Sendable {
        public let name: String
        public let city: String?
        public let region: String?
        public let country: String?
        public let imageURL: URL?

        public init(name: String, city: String?, region: String?, country: String?, imageURL: URL?) {
            self.name = name
            self.city = city
            self.region = region
            self.country = country
            self.imageURL = imageURL
        }

        /// e.g. "Atlanta, GA"
        public var place: String? {
            let parts = [city, region].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    /// Averaged across every sportsbook the provider lists.
    public struct Odds: Hashable, Sendable {
        /// The books averaged, e.g. ["DraftKings"].
        public let books: [String]
        /// Home team's line: negative when home is favoured.
        public let homeSpread: Double?
        public let overUnder: Double?
        public let homeMoneyLine: Int?
        public let awayMoneyLine: Int?

        public init(books: [String], homeSpread: Double?, overUnder: Double?, homeMoneyLine: Int?, awayMoneyLine: Int?) {
            self.books = books
            self.homeSpread = homeSpread
            self.overUnder = overUnder
            self.homeMoneyLine = homeMoneyLine
            self.awayMoneyLine = awayMoneyLine
        }
    }

    /// A team's place in its division or conference, e.g. 2nd in "NFC South".
    public struct Standing: Hashable, Sendable {
        public let teamID: Team.ID
        public let group: String
        public let position: Int
        public let record: String?

        public init(teamID: Team.ID, group: String, position: Int, record: String?) {
            self.teamID = teamID
            self.group = group
            self.position = position
            self.record = record
        }
    }

    /// A leader in a category: season leaders before kickoff, game leaders once it starts.
    public struct Leader: Hashable, Sendable {
        public let teamID: Team.ID
        /// e.g. "Passing Yards"
        public let category: String
        public let athlete: String
        /// Full stat line, e.g. "21/29, 264 YDS, 1 TD".
        public let line: String
        /// e.g. "B. Purdy"
        public let shortName: String?
        public let position: String?
        public let headshotURL: URL?
        /// The headline number, e.g. "264".
        public let mainValue: String?
        /// The rest, e.g. "21/29, 1 TD".
        public let summary: String?

        public init(teamID: Team.ID, category: String, athlete: String, line: String, shortName: String? = nil,
                    position: String? = nil, headshotURL: URL? = nil, mainValue: String? = nil, summary: String? = nil) {
            self.teamID = teamID
            self.category = category
            self.athlete = athlete
            self.line = line
            self.shortName = shortName
            self.position = position
            self.headshotURL = headshotURL
            self.mainValue = mainValue
            self.summary = summary
        }
    }

    public let venue: Venue?
    public let attendance: Int?
    /// e.g. ["Fox"]
    public let broadcasts: [String]
    public let odds: Odds?
    public let standings: [Standing]
    /// Pre-game win chance (0–100) by team ID.
    public let winProbability: [Team.ID: Double]
    public let leaders: [Leader]
    /// ESPN's written game story, once a finished game has one.
    public let recap: Recap?

    /// A published game story: headline, body paragraphs and a link to the full article.
    public struct Recap: Hashable, Sendable {
        public let headline: String
        public let paragraphs: [String]
        public let url: URL?

        public init(headline: String, paragraphs: [String], url: URL?) {
            self.headline = headline
            self.paragraphs = paragraphs
            self.url = url
        }
    }

    public init(venue: Venue? = nil, attendance: Int? = nil, broadcasts: [String] = [], odds: Odds? = nil,
                standings: [Standing] = [], winProbability: [Team.ID: Double] = [:], leaders: [Leader] = [],
                recap: Recap? = nil) {
        self.venue = venue
        self.attendance = attendance
        self.broadcasts = broadcasts
        self.odds = odds
        self.standings = standings
        self.winProbability = winProbability
        self.leaders = leaders
        self.recap = recap
    }
}

/// Conditions at a place and time.
public struct Weather: Hashable, Sendable {
    public let temperature: Measurement<UnitTemperature>
    /// WMO weather code (0 clear … 95 thunderstorm).
    public let code: Int
    public let windSpeed: Measurement<UnitSpeed>?
    /// Percent chance.
    public let precipitationChance: Int?

    public init(temperature: Measurement<UnitTemperature>, code: Int,
                windSpeed: Measurement<UnitSpeed>?, precipitationChance: Int?) {
        self.temperature = temperature
        self.code = code
        self.windSpeed = windSpeed
        self.precipitationChance = precipitationChance
    }

    /// Plain-English summary of the WMO code.
    public var summary: String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "Mixed"
        }
    }
}
