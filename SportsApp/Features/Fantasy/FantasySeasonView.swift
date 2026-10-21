import Charts
import SportsKit
import SwiftUI

/// Season tab: your starters' actual points against projection over the completed weeks, where the
/// gap comes from (by position and by player), and the league standings.
struct FantasySeasonView: View {
    let trend: SeasonTrend
    let standings: [FantasyStanding]

    /// The week under the pointer on the chart.
    @State private var hoveredWeek: Int?

    var body: some View {
        if trend.weeks.isEmpty {
            ContentUnavailableView("No Completed Weeks", systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Season numbers appear once a week has been played."))
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            SportsCard(title: "Season Trend") {
                Text(summary).font(.body).padding(.vertical, 4)
            }
            // Equal heights: the row sizes to its tallest tile, and every tile stretches to it.
            HStack(alignment: .top, spacing: 12) {
                tile("Actual per week", Self.number(trend.actualPerWeek), "Completed weeks, starters only")
                tile("Projected per week", Self.number(trend.projectedPerWeek), "Same weeks")
                tile("Gap per week", Self.signed(trend.gapPerWeek), "Actual minus projected", color: trend.gapPerWeek >= 0 ? .green : .red)
                if let leak = trend.gapByPosition.first, leak.gap < 0 {
                    tile("Biggest leak", leak.position, "\(Self.signed(leak.gap)) per start vs projection", color: .red)
                } else {
                    tile("Biggest leak", "None", "Every position at or above projection")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            chart
            HStack(alignment: .top, spacing: 12) {
                SportsCard(title: "Average Gap by Position") {
                    Text("Actual minus projected, per start. Right of zero beats projection.")
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                    GapBars(rows: trend.gapByPosition.map { ($0.position, $0.gap) })
                }
                SportsCard(title: "Total Gap by Starter") {
                    Text("Points above or below projection across all starts.")
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                    GapBars(rows: trend.gapByStarter.map { ($0.name, $0.gap) })
                }
            }
            if !standings.isEmpty {
                standingsCard
            }
        }
    }

    /// "Actual points are running +3.9 per week against projection. QB beats projection most (+7.3 per start); RB is the biggest leak (−2.5)."
    private var summary: String {
        var text = "Actual points are running \(Self.signed(trend.gapPerWeek)) per week against projection."
        if let best = trend.gapByPosition.last, let worst = trend.gapByPosition.first, best.position != worst.position {
            text += " \(best.position) beats projection most (\(Self.signed(best.gap)) per start); \(worst.position) is the biggest leak (\(Self.signed(worst.gap)))."
        }
        return text
    }

    private func tile(_ title: String, _ value: String, _ caption: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.score(28)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.black.opacity(0.38), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
    }

    private var chart: some View {
        SportsCard(title: "Weekly Points: Projected vs Actual") {
            Chart {
                if let week = trend.weeks.first(where: { $0.week == hoveredWeek }) {
                    RuleMark(x: .value("Week", week.week))
                        .foregroundStyle(.white.opacity(0.5))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            callout(week)
                        }
                }
                ForEach(trend.weeks, id: \.week) { week in
                    LineMark(x: .value("Week", week.week), y: .value("Points", week.projected), series: .value("Series", "Projected"))
                        .foregroundStyle(.gray)
                    PointMark(x: .value("Week", week.week), y: .value("Points", week.projected))
                        .foregroundStyle(.gray).symbolSize(25)
                    LineMark(x: .value("Week", week.week), y: .value("Points", week.actual), series: .value("Series", "Actual"))
                        .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Week", week.week), y: .value("Points", week.actual))
                        .foregroundStyle(.green).symbolSize(45)
                        .annotation(position: week.actual >= week.projected ? .top : .bottom) {
                            if week.week != hoveredWeek {
                                Text(Self.number(week.actual)).font(.caption2.weight(.semibold))
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: trend.weeks.map(\.week)) { value in
                    AxisValueLabel { Text("Wk \(value.as(Int.self) ?? 0)") }
                }
            }
            // Half a week of room each side, so the first and last labels aren't clipped.
            .chartXScale(domain: 0.5...(Double(trend.weeks.last?.week ?? 1) + 0.5))
            .chartForegroundStyleScale(["Projected": Color.gray, "Actual": Color.green])
            .chartLegend(position: .top, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame,
                                      let x = proxy.value(atX: location.x - geometry[frame].origin.x, as: Double.self)
                                else { return }
                                hoveredWeek = trend.weeks.min { abs(Double($0.week) - x) < abs(Double($1.week) - x) }?.week
                            case .ended:
                                hoveredWeek = nil
                            }
                        }
                }
            }
            .frame(height: 260)
            .padding(.top, 30) // room for the hover callout
            .padding(.vertical, 8)
        }
    }

    /// "Week 3 · Actual 67.7 · Projected 102.5 · −34.8"
    private func callout(_ week: FantasyWeekResult) -> some View {
        VStack(spacing: 2) {
            Text("Week \(week.week)").font(.caption.weight(.semibold))
            Text("Actual \(Self.number(week.actual)) · Projected \(Self.number(week.projected))").font(.caption.monospacedDigit())
            Text(Self.signed(week.actual - week.projected)).font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(week.actual >= week.projected ? .green : .red)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.black.opacity(0.75), in: .rect(cornerRadius: 8))
    }

    private var standingsCard: some View {
        let maxPoints = standings.map(\.pointsFor).max() ?? 1
        return SportsCard(title: "League Standings") {
            Text("By record, then points for. Your row is highlighted.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            HStack(spacing: 12) {
                Text("Rank").frame(width: 36, alignment: .leading)
                Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("Record").frame(width: 56, alignment: .leading)
                Text("Points For").frame(width: 220, alignment: .leading)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, team in
                HStack(spacing: 12) {
                    Text("\(index + 1)").monospacedDigit().frame(width: 36, alignment: .leading)
                    Text(team.teamName).fontWeight(team.isMine ? .bold : .regular).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(team.record).monospacedDigit().frame(width: 56, alignment: .leading)
                    // Points for, with a bar against the league's best.
                    Text(Self.number(team.pointsFor)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .frame(width: 220, alignment: .leading)
                        .background(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1)).frame(width: 220 * team.pointsFor / maxPoints)
                        }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background {
                    // Your row floats as a green-tinted Liquid Glass capsule.
                    if team.isMine {
                        Capsule().fill(.clear).glassEffect(.regular.tint(.green.opacity(0.35)), in: .capsule)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
    static func signed(_ value: Double) -> String { (value >= 0 ? "+" : "−") + number(abs(value)) }
}

/// Horizontal bars either side of zero: red for below projection, green for above.
private struct GapBars: View {
    let rows: [(label: String, value: Double)]

    var body: some View {
        let scale = max(rows.map { abs($0.value) }.max() ?? 1, 0.1)
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                HStack(spacing: 8) {
                    Text(row.label).font(.caption).lineLimit(1).frame(width: 120, alignment: .trailing)
                    GeometryReader { geometry in
                        let half = geometry.size.width / 2
                        let width = max(2, half * abs(row.value) / scale)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.2)).frame(width: 1).offset(x: half)
                            RoundedRectangle(cornerRadius: 3).fill(row.value >= 0 ? Color.green : Color.red)
                                .frame(width: width)
                                .offset(x: row.value >= 0 ? half : half - width)
                        }
                    }
                    .frame(height: 14)
                    Text(FantasySeasonView.signed(row.value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label) \(FantasySeasonView.signed(row.value))")
            }
        }
    }
}
