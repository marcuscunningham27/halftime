public struct League: Identifiable, Hashable, Sendable {
    /// How a sport divides a game; drives period labels and which alerts make sense.
    public enum PeriodStyle: Hashable, Sendable {
        case quarters, periods, innings, halves

        public var regulationPeriods: Int {
            switch self {
            case .quarters: 4
            case .periods: 3
            case .innings: 9
            case .halves: 2
            }
        }
    }

    /// Stable, provider-independent slug, e.g. "nfl".
    public let id: String
    public let name: String
    public let abbreviation: String
    public let periodStyle: PeriodStyle
    /// A game is "close" within this margin...
    public let closeGameMargin: Int
    /// ...with this many seconds or fewer left in the last regulation period or later.
    public let closeGameSeconds: Int

    public init(id: String, name: String, abbreviation: String, periodStyle: PeriodStyle = .quarters,
                closeGameMargin: Int = 8, closeGameSeconds: Int = 300) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.periodStyle = periodStyle
        self.closeGameMargin = closeGameMargin
        self.closeGameSeconds = closeGameSeconds
    }

    public var regulationPeriods: Int { periodStyle.regulationPeriods }

    /// Line score header, e.g. "3", "OT", "2OT", "ET", "11".
    public func periodLabel(_ period: Int) -> String {
        guard period > regulationPeriods else { return "\(period)" }
        let extra = period - regulationPeriods
        switch periodStyle {
        case .innings: return "\(period)"
        case .halves: return "ET"
        case .quarters, .periods: return extra == 1 ? "OT" : "\(extra)OT"
        }
    }

    /// Section title, e.g. "Quarter 3", "Second Half", "Overtime".
    public func periodTitle(_ period: Int) -> String {
        switch periodStyle {
        case .innings: return "Inning \(period)"
        case .halves: return period == 1 ? "First Half" : period == 2 ? "Second Half" : "Extra Time"
        case .quarters, .periods:
            guard period > regulationPeriods else { return "\(periodStyle == .quarters ? "Quarter" : "Period") \(period)" }
            let extra = period - regulationPeriods
            return extra == 1 ? "Overtime" : "Overtime \(extra)"
        }
    }

    public static let nfl = League(id: "nfl", name: "National Football League", abbreviation: "NFL",
                                   closeGameMargin: 8, closeGameSeconds: 300)
    public static let nba = League(id: "nba", name: "National Basketball Association", abbreviation: "NBA",
                                   closeGameMargin: 5, closeGameSeconds: 120)
    public static let mlb = League(id: "mlb", name: "Major League Baseball", abbreviation: "MLB", periodStyle: .innings)
    public static let nhl = League(id: "nhl", name: "National Hockey League", abbreviation: "NHL", periodStyle: .periods,
                                   closeGameMargin: 1, closeGameSeconds: 300)
    public static let epl = League(id: "epl", name: "Premier League", abbreviation: "EPL", periodStyle: .halves)
    public static let afl = League(id: "afl", name: "Australian Football League", abbreviation: "AFL")
    public static let nrl = League(id: "nrl", name: "National Rugby League", abbreviation: "NRL", periodStyle: .halves)

    /// Every league the app knows about, in sidebar order; providers say which ones they can serve.
    public static let all: [League] = [.nfl, .nba, .mlb, .nhl, .epl, .afl, .nrl]

    public static func with(id: League.ID) -> League? {
        all.first { $0.id == id }
    }
}
