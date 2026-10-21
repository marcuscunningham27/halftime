import Foundation

/// ESPN's per-play probabilities (all 0–1, from the home team's side except `over`).
public struct ProbabilityPoint: Hashable, Sendable {
    public let playID: String
    public let homeWin: Double
    /// Chance the home team covers the market spread.
    public let homeCover: Double?
    /// Chance the game goes over the market total.
    public let over: Double?

    public init(playID: String, homeWin: Double, homeCover: Double?, over: Double?) {
        self.playID = playID
        self.homeWin = homeWin
        self.homeCover = homeCover
        self.over = over
    }
}

/// A probability point placed on the game clock, ready to chart.
public struct ChartPoint: Hashable, Sendable, Identifiable {
    public var id: String { playID }
    public let playID: String
    /// 0 at kickoff, 1 at the end of regulation (beyond 1 in overtime).
    public let progress: Double
    public let homeWin: Double
    public let homeCover: Double?
    public let over: Double?
    /// Regulation seconds left, where the sport has a countdown clock.
    public let secondsLeft: Double?
    public let homeScore: Int
    public let awayScore: Int
    /// The play's period and clock, for "2nd 5:32"-style readouts.
    public let period: Int
    public let clock: String
}

/// Joins probabilities to plays and re-prices cover chances for a line other than the market's.
public enum Probability {
    /// Lines the app can re-price, with each sport's typical spread of outcomes at kickoff.
    struct Model {
        let periodSeconds: Double
        let marginSigma: Double
        let totalSigma: Double
    }

    static let models: [League.ID: Model] = [
        League.nfl.id: Model(periodSeconds: 900, marginSigma: 13.86, totalSigma: 10),
        League.nba.id: Model(periodSeconds: 720, marginSigma: 12, totalSigma: 17),
    ]

    public static func supportsCustomLines(_ league: League) -> Bool { models[league.id] != nil }

    /// Places each point at its play's moment; points without a matching play are dropped.
    public static func chart(_ points: [ProbabilityPoint], plays: [Play], league: League) -> [ChartPoint] {
        let byID = Dictionary(plays.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let model = models[league.id]
        let matched = points.compactMap { point in byID[point.playID].map { (point, $0) } }
        var lastAway = 0, lastHome = 0
        let points: [ChartPoint] = matched.enumerated().compactMap { index, pair in
            let (point, play) = pair
            lastAway = play.awayScore ?? lastAway
            lastHome = play.homeScore ?? lastHome
            let left = model.flatMap { secondsLeft(play, league: league, periodSeconds: $0.periodSeconds) }
            // A timed sport's play without a readable clock can't be placed; guessing would draw lines back across the chart.
            if model != nil && left == nil { return nil }
            let progress: Double
            if let left, let model {
                let regulation = model.periodSeconds * Double(league.regulationPeriods)
                if play.period > league.regulationPeriods, let clock = clockSeconds(play) {
                    // Each overtime period takes a further 15% of the chart width.
                    let overtime = Double(play.period - league.regulationPeriods - 1)
                    progress = 1 + 0.15 * (overtime + 1 - min(clock / model.periodSeconds, 1))
                } else {
                    progress = 1 - left / regulation
                }
            } else {
                progress = matched.count > 1 ? Double(index) / Double(matched.count - 1) : 0
            }
            return ChartPoint(playID: point.playID, progress: progress, homeWin: point.homeWin, homeCover: point.homeCover,
                              over: point.over, secondsLeft: left, homeScore: lastHome, awayScore: lastAway,
                              period: play.period, clock: play.clock)
        }
        // Time order, in case the feed lists plays out of order (stable, so ties keep feed order).
        return points.enumerated().sorted { ($0.element.progress, $0.offset) < ($1.element.progress, $1.offset) }.map(\.element)
    }

    /// Seconds on the clock at a play: "m:ss", or plain seconds ("45.3") as basketball shows in a period's last minute.
    static func clockSeconds(_ play: Play) -> Double? {
        let parts = play.clock.split(separator: ":").map { Double($0) }
        guard !parts.contains(nil) else { return nil }
        switch parts.count {
        case 2: return parts[0]! * 60 + parts[1]!
        case 1: return parts[0]!
        default: return nil
        }
    }

    static func secondsLeft(_ play: Play, league: League, periodSeconds: Double) -> Double? {
        guard let inPeriod = clockSeconds(play) else { return nil }
        let remainingPeriods = max(0, league.regulationPeriods - play.period)
        return play.period > league.regulationPeriods ? 0 : inPeriod + Double(remainingPeriods) * periodSeconds
    }

    /// Home cover chance for `line` (home team's spread, negative when favoured), from ESPN's chance at `marketLine`.
    /// Shifts the market probability by the line difference over the uncertainty left; settles exactly at full time.
    public static func homeCover(at point: ChartPoint, line: Double, marketLine: Double, league: League, final: Bool) -> Double? {
        guard let market = point.homeCover, let model = models[league.id] else { return nil }
        let margin = Double(point.homeScore - point.awayScore)
        if final && point.secondsLeft == 0 { return margin + line > 0 ? 1 : (margin + line == 0 ? 0.5 : 0) }
        guard line != marketLine else { return market }
        let sigma = remainingSigma(model.marginSigma, point: point, model: model, league: league)
        return shift(market, by: (line - marketLine) / sigma)
    }

    /// Over chance for `total`, from ESPN's chance at `marketTotal`.
    public static func over(at point: ChartPoint, total: Double, marketTotal: Double, league: League, final: Bool) -> Double? {
        guard let market = point.over, let model = models[league.id] else { return nil }
        let points = Double(point.homeScore + point.awayScore)
        if final && point.secondsLeft == 0 { return points > total ? 1 : (points == total ? 0.5 : 0) }
        guard total != marketTotal else { return market }
        let sigma = remainingSigma(model.totalSigma, point: point, model: model, league: league)
        return shift(market, by: -(total - marketTotal) / sigma)
    }

    private static func remainingSigma(_ full: Double, point: ChartPoint, model: Model, league: League) -> Double {
        let regulation = model.periodSeconds * Double(league.regulationPeriods)
        let fraction = (point.secondsLeft ?? regulation) / regulation
        return max(full * fraction.squareRoot(), 0.5)
    }

    /// Moves a probability by `z` standard deviations.
    static func shift(_ p: Double, by z: Double) -> Double {
        normalCDF(inverseNormalCDF(min(max(p, 0.001), 0.999)) + z)
    }

    static func normalCDF(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Acklam's rational approximation (error ~1e-9).
    static func inverseNormalCDF(_ p: Double) -> Double {
        let a = [-39.69683028665376, 220.9460984245205, -275.9285104469687, 138.3577518672690, -30.66479806614716, 2.506628277459239]
        let b = [-54.47609879822406, 161.5858368580409, -155.6989798598866, 66.80131188771972, -13.28068155288572]
        let c = [-0.007784894002430293, -0.3223964580411365, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783]
        let d = [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416]
        let low = 0.02425
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > 1 - low {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5, r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }
}
