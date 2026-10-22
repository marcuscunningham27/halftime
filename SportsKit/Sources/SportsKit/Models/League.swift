import Foundation

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
    public static let wnba = League(id: "wnba", name: "Women's National Basketball Association", abbreviation: "WNBA",
                                    closeGameMargin: 5, closeGameSeconds: 120)
    public static let mlb = League(id: "mlb", name: "Major League Baseball", abbreviation: "MLB", periodStyle: .innings)
    public static let nhl = League(id: "nhl", name: "National Hockey League", abbreviation: "NHL", periodStyle: .periods,
                                   closeGameMargin: 1, closeGameSeconds: 300)
    public static let epl = League(id: "epl", name: "Premier League", abbreviation: "EPL", periodStyle: .halves)
    public static let ucl = League(id: "ucl", name: "UEFA Champions League", abbreviation: "UCL", periodStyle: .halves)
    public static let mls = League(id: "mls", name: "Major League Soccer", abbreviation: "MLS", periodStyle: .halves)

    /// Every league the app knows about, in sidebar order; providers say which ones they can serve.
    /// AFL and NRL were dropped (Oct 2026): ESPN's data for them is too thin. Follows of theirs are pruned on launch.
    public static let all: [League] = [.nfl, .nba, .wnba, .mlb, .nhl, .epl, .ucl, .mls]

    /// ESPN's league logo, for section headers. Soccer logos are filed under ESPN's numeric league IDs.
    public var logoURL: URL? {
        let soccer = [League.epl.id: 23, League.ucl.id: 2, League.mls.id: 19]
        return URL(string: soccer[id].map { "https://a.espncdn.com/i/leaguelogos/soccer/500/\($0).png" }
            ?? "https://a.espncdn.com/i/teamlogos/leagues/500/\(id).png")
    }

    public static func with(id: League.ID) -> League? {
        all.first { $0.id == id }
    }
}
