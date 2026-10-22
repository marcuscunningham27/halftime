import Foundation

/// Every notifiable event type, with SPEC.md's defaults. Adding one means a case here and a rule in the detector.
public enum NotificationEvent: String, CaseIterable, Identifiable, Sendable {
    case gameStart, scoreUpdate, periodEnd, halftime, final, redZone, closeGame, overtime, leadChange

    public var id: Self { self }

    public var title: String {
        switch self {
        case .gameStart: "Game start"
        case .scoreUpdate: "Score updates"
        case .periodEnd: "Period end"
        case .halftime: "Halftime"
        case .final: "Final score"
        case .redZone: "Red zone"
        case .closeGame: "Close game, final minutes"
        case .overtime: "Overtime"
        case .leadChange: "Lead changes"
        }
    }

    public var isOnByDefault: Bool {
        switch self {
        case .gameStart, .scoreUpdate, .final, .overtime: true
        case .periodEnd, .halftime, .redZone, .closeGame, .leadChange: false
        }
    }

    public func applies(to league: League) -> Bool {
        switch self {
        case .redZone: league.id == League.nfl.id
        case .closeGame: [League.nfl.id, League.nba.id, League.wnba.id, League.nhl.id].contains(league.id)
        // Innings and halves would spam or duplicate halftime.
        case .periodEnd: [.quarters, .periods].contains(league.periodStyle)
        case .halftime: [.quarters, .halves].contains(league.periodStyle)
        default: true
        }
    }
}

public struct GameEvent: Hashable, Sendable {
    public let type: NotificationEvent
    /// Stable per occurrence, so the same event is never sent twice (see NotificationLog).
    public let key: String
    /// e.g. "Red Zone"
    public let headline: String
    public let body: String
}

/// Diffs consecutive snapshots of a game into events. Keeps a little state for red zone,
/// which must fire once per drive even if the offence leaves and re-enters the red zone.
public struct GameEventDetector: Sendable {
    /// Games whose current possession has already had its red zone alert.
    private var redZoneAlerted: [Game.ID: Team.ID] = [:]

    public init() {}

    /// Pass nil for `old` on the first sighting of a game; that only records state.
    public mutating func events(old: Game?, new game: Game) -> [GameEvent] {
        let league = game.league
        let redZone = redZoneEvent(new: game)
        guard let old else { return [] }

        var events: [GameEvent] = []
        func add(_ type: NotificationEvent, _ key: String, _ headline: String, _ body: String? = nil) {
            events.append(GameEvent(type: type, key: key, headline: headline, body: body ?? game.scoreLine))
        }

        if old.status == .scheduled, game.status == .live {
            add(.gameStart, "start", "Kickoff", "\(game.away.team.shortName) at \(game.home.team.shortName) has started.")
        }
        // nil (not started) counts as 0, so kickoff isn't a score change.
        if game.status != .scheduled, (game.away.score ?? 0) != (old.away.score ?? 0) || (game.home.score ?? 0) != (old.home.score ?? 0) {
            add(.scoreUpdate, "score-\(game.away.score ?? 0)-\(game.home.score ?? 0)", "Score Update")
            if let before = old.leader, let after = game.leader, before.team.id != after.team.id {
                add(.leadChange, "lead-\(game.away.score ?? 0)-\(game.home.score ?? 0)", "Lead Change",
                    "\(after.team.shortName) lead \(game.scoreLine)")
            }
        }
        if game.intermission == .endOfPeriod, old.intermission != .endOfPeriod {
            add(.periodEnd, "period-\(game.period)", "End of \(league.periodTitle(game.period))")
        }
        if game.intermission == .halftime, old.intermission != .halftime {
            add(.halftime, "halftime", "Halftime")
        }
        if game.status == .live, game.period > league.regulationPeriods, old.period <= league.regulationPeriods {
            add(.overtime, "overtime", "Overtime")
        }
        if game.isClose(league), !old.isClose(league) {
            add(.closeGame, "close", "Close Game")
        }
        if game.status == .final, old.status != .final {
            add(.final, "final", "Final")
        }
        if let redZone { events.append(redZone) }
        return events
    }

    private mutating func redZoneEvent(new game: Game) -> GameEvent? {
        guard game.status == .live, let situation = game.situation, let offense = situation.possessionTeamID else {
            return nil
        }
        // A new possession is a new drive, so it may alert again.
        if redZoneAlerted[game.id] != nil, redZoneAlerted[game.id] != offense {
            redZoneAlerted[game.id] = nil
        }
        guard situation.isRedZone, redZoneAlerted[game.id] == nil else { return nil }
        redZoneAlerted[game.id] = offense
        let team = offense == game.home.team.id ? game.home.team : game.away.team
        let spot = situation.downAndDistance.map { ": " + $0.replacingOccurrences(of: "&", with: "and") } ?? ""
        return GameEvent(type: .redZone, key: "redzone-\(offense)-\(game.period)-\(game.clock)",
                         headline: "Red Zone", body: "\(team.shortName) in the red zone\(spot)")
    }
}

extension Game {
    /// e.g. "WSH 3 – 27 SF · 7:25 - 3rd"
    public var scoreLine: String {
        "\(away.team.abbreviation) \(away.score ?? 0) – \(home.score ?? 0) \(home.team.abbreviation) · \(statusDetail)"
    }

    var leader: Competitor? {
        let away = away.score ?? 0, home = home.score ?? 0
        return away == home ? nil : (away > home ? self.away : self.home)
    }

    public var league: League {
        League.with(id: leagueID) ?? League(id: leagueID, name: leagueID, abbreviation: leagueID.uppercased())
    }

    /// Short period for the menu bar: "Q3", "P2", "OT", "Half", or the provider's text where
    /// it says more than a number ("Top 8th", "67'").
    public var compactPeriod: String {
        if intermission == .halftime { return "Half" }
        switch league.periodStyle {
        case .innings, .halves: return statusDetail
        case .quarters, .periods:
            guard period <= league.regulationPeriods else { return league.periodLabel(period) }
            return "\(league.periodStyle == .quarters ? "Q" : "P")\(period)"
        }
    }

    func isClose(_ league: League) -> Bool {
        guard status == .live, period >= league.regulationPeriods, let seconds = clockSeconds else { return false }
        return seconds <= league.closeGameSeconds && abs((away.score ?? 0) - (home.score ?? 0)) <= league.closeGameMargin
    }

    /// Parses "m:ss"; nil for anything else.
    var clockSeconds: Int? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
    }
}
