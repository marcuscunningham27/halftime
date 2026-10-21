import Charts
import SportsKit
import SwiftUI

/// ESPN-style probability chart: win chance, or the chance of covering a spread or going over a total.
/// The line starts at the market's (from the Overview odds) and can be changed for your own bet.
struct ProbabilityView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case win = "Win Probability", cover = "Cover Probability"
        var id: Self { self }
    }

    enum Market: String, CaseIterable, Identifiable {
        case spread = "Spread", total = "Total"
        var id: Self { self }
    }

    let provider: any SportsProvider
    let game: Game
    let detail: GameDetail

    @State private var points: [ProbabilityPoint] = []
    @State private var mode = Mode.win
    @State private var market = Market.spread
    /// The home team's spread and the total being priced; nil means the market's.
    @State private var customSpread: Double?
    @State private var customTotal: Double?
    /// Chart position under the pointer (0 = kickoff, 1 = end of regulation).
    @State private var hoverProgress: Double?

    private var chart: [ChartPoint] {
        Probability.chart(points, plays: detail.plays, league: game.league)
    }

    private var marketSpread: Double? { detail.overview.odds?.homeSpread }
    private var marketTotal: Double? { detail.overview.odds?.overUnder }
    private var spread: Double? { customSpread ?? marketSpread }
    private var total: Double? { customTotal ?? marketTotal }
    private var hasCover: Bool { chart.contains { $0.homeCover != nil } && marketSpread != nil }

    var body: some View {
        Group {
            if !chart.isEmpty {
                SportsCard(title: "Probabilities") {
                    if hasCover {
                        GlassPicker(selection: $mode)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                    }
                    if mode == .cover, hasCover {
                        lineControls.padding(.bottom, 6)
                    }
                    content
                }
            } else {
                // Gives .task a view to run on; an empty Group never appears, so nothing would ever load.
                Color.clear.frame(height: 1)
            }
        }
        // Reload whenever the play list grows, so a live chart keeps up.
        .task(id: detail.plays.count) {
            points = (try? await provider.probabilities(for: game)) ?? points
        }
    }

    /// Values plotted from the away side (top of the chart): away win, away cover, or over.
    private var series: [(point: ChartPoint, progress: Double, value: Double)] {
        chart.compactMap { point in
            let final = game.status == .final
            switch (mode, market) {
            case (.win, _):
                return (point, point.progress, 1 - point.homeWin)
            case (.cover, .spread):
                guard let spread, let marketSpread else { return nil }
                return Probability.homeCover(at: point, line: spread, marketLine: marketSpread, league: game.league, final: final)
                    .map { (point, point.progress, 1 - $0) }
            case (.cover, .total):
                guard let total, let marketTotal else { return nil }
                return Probability.over(at: point, total: total, marketTotal: marketTotal, league: game.league, final: final)
                    .map { (point, point.progress, $0) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let values = series
        // While hovering, everything reads the moment under the pointer instead of the latest.
        let hovered = hoverProgress.flatMap { x in values.min { abs($0.progress - x) < abs($1.progress - x) } }
        let current = hovered?.value ?? values.last?.value ?? 0.5
        sideRow(top: true, value: current)
        Chart {
            RuleMark(y: .value("Even", 0.5)).foregroundStyle(.white.opacity(0.35))
            if let hovered {
                RuleMark(x: .value("Moment", hovered.progress))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(hovered.point, value: hovered.value)
                    }
                PointMark(x: .value("Moment", hovered.progress), y: .value("Chance", hovered.value))
                    .foregroundStyle(.white)
                    .symbolSize(40)
            }
            ForEach(Array(values.enumerated()), id: \.offset) { _, point in
                // Shade toward whichever side is ahead, in its colour.
                AreaMark(x: .value("Game", point.progress), yStart: .value("Even", 0.5), yEnd: .value("Top", max(point.value, 0.5)),
                         series: .value("Side", "top"))
                    .foregroundStyle(topColor.opacity(0.35))
                AreaMark(x: .value("Game", point.progress), yStart: .value("Bottom", min(point.value, 0.5)), yEnd: .value("Even", 0.5),
                         series: .value("Side", "bottom"))
                    .foregroundStyle(game.home.team.color.opacity(0.35))
                LineMark(x: .value("Game", point.progress), y: .value("Chance", point.value))
                    .foregroundStyle(.white.opacity(0.85))
                    .interpolationMethod(.linear)
            }
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 0...max(1, values.last?.progress ?? 1))
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel { Text(value.as(Double.self) == 0.5 ? "50" : "100") }
            }
        }
        .chartXAxis {
            AxisMarks(values: periodBoundaries) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            AxisMarks(values: periodCentres) { value in
                AxisValueLabel {
                    if let x = value.as(Double.self), let index = periodCentres.firstIndex(of: x) {
                        Text(Game.ordinal(index + 1))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            hoverProgress = proxy.value(atX: location.x - geometry[frame].origin.x, as: Double.self)
                        case .ended:
                            hoverProgress = nil
                        }
                    }
            }
        }
        .frame(height: 220)
        .padding(.top, 34) // room for the hover callout above the chart
        .padding(.bottom, 6)
        sideRow(top: false, value: 1 - current)
        if mode == .cover {
            Text(footnote).font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
        }
    }

    /// "2nd 5:32 · WSH 10–13 SF" with the hovered chance.
    private func callout(_ point: ChartPoint, value: Double) -> some View {
        let top = mode == .cover && market == .total ? "Over" : game.away.team.abbreviation
        let bottom = mode == .cover && market == .total ? "Under" : game.home.team.abbreviation
        return VStack(spacing: 2) {
            Text("\(game.league.periodStyle == .innings ? "Inning \(point.period)" : point.period <= game.league.regulationPeriods ? Game.ordinal(point.period) : game.league.periodLabel(point.period)) \(point.clock)")
                .font(.caption.weight(.semibold))
            Text("\(top) \(Int((value * 100).rounded()))% · \(bottom) \(Int(((1 - value) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
            Text("\(game.away.team.abbreviation) \(point.awayScore)–\(point.homeScore) \(game.home.team.abbreviation)")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.black.opacity(0.75), in: .rect(cornerRadius: 8))
    }

    private var periodCentres: [Double] {
        let n = game.league.regulationPeriods
        return (0..<n).map { (Double($0) + 0.5) / Double(n) }
    }

    private var periodBoundaries: [Double] {
        let n = game.league.regulationPeriods
        return (1..<n).map { Double($0) / Double(n) }
    }

    private var topColor: Color {
        mode == .cover && market == .total ? .green : game.away.team.color
    }

    /// Team (or Over/Under) with its current chance and, for cover, its line.
    private func sideRow(top: Bool, value: Double) -> some View {
        let team = top ? game.away.team : game.home.team
        return HStack(spacing: 8) {
            if mode == .cover && market == .total {
                Image(systemName: top ? "arrow.up.circle.fill" : "arrow.down.circle.fill").font(.title2)
                Text(top ? "Over" : "Under").font(.headline)
            } else {
                TeamLogo(team: team, size: 28)
                Text(team.abbreviation).font(.headline)
            }
            Spacer()
            if mode == .cover, let line = lineLabel(top: top) {
                Text(line).font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 6))
            }
            Text("\(Int((value * 100).rounded()))%").font(.score(30)).monospacedDigit()
        }
    }

    private func lineLabel(top: Bool) -> String? {
        switch market {
        case .spread:
            guard let spread else { return nil }
            let line = top ? -spread : spread // the away line is the home line flipped
            return line > 0 ? "+\(Self.format(line))" : line == 0 ? "PK" : "−\(Self.format(-line))"
        case .total:
            return total.map { Self.format($0) }
        }
    }

    private var lineControls: some View {
        HStack(spacing: 12) {
            GlassPicker(selection: $market)
            if Probability.supportsCustomLines(game.league) {
                switch market {
                case .spread:
                    Stepper("\(game.home.team.abbreviation) \(lineLabel(top: false) ?? "")",
                            value: Binding(get: { spread ?? 0 }, set: { customSpread = $0 }), step: 0.5)
                case .total:
                    Stepper("Total \(total.map { Self.format($0) } ?? "")",
                            value: Binding(get: { total ?? 0 }, set: { customTotal = $0 }), step: 0.5)
                }
                if (market == .spread ? customSpread : customTotal) != nil {
                    Button("Market Line") {
                        if market == .spread { customSpread = nil } else { customTotal = nil }
                    }
                    .buttonStyle(.glass)
                }
            }
            Spacer()
        }
        .font(.subheadline)
    }

    private var footnote: String {
        let custom = market == .spread ? customSpread != nil : customTotal != nil
        let books = detail.overview.odds?.books.joined(separator: ", ") ?? "the market"
        return custom
            ? "ESPN's probabilities at the \(books) line, adjusted to your line by the points between them and the time left. An estimate."
            : "ESPN's probabilities at the \(books) line."
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
