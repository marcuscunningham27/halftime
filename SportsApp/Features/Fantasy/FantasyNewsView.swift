import SportsKit
import SwiftUI

/// News tab: who's out or on bye, an injury report across the roster, the latest news, and the
/// weeks ahead where byes leave a starting slot nobody can fill.
struct FantasyNewsView: View {
    let base: FantasyView.Base

    private var players: [FantasyPlayer] { base.team.players }

    private func onBye(_ player: FantasyPlayer) -> Bool {
        player.team.flatMap { base.byes[$0] } == base.upcomingWeek
    }

    var body: some View {
        SportsCard(title: "Roster News") {
            Text(summary).font(.body).padding(.vertical, 4)
            Text("Statuses come from \(base.league.provider.title). News is from ESPN’s fantasy feed (Rotowire).")
                .font(.caption).foregroundStyle(.secondary)
        }
        byeHoles
        injuryReport
        latestNews
    }

    /// "1 out (Jacory Croskey-Merritt) · 1 on bye (Sam LaPorta) · 12 healthy"
    private var summary: String {
        let hurt = players.filter { ($0.injury?.severity ?? 0) >= 3 }
        let questionable = players.filter { (1...2).contains($0.injury?.severity ?? 0) }
        let bye = players.filter { onBye($0) && ($0.injury?.severity ?? 0) < 3 }
        let healthy = players.count - hurt.count - questionable.count - bye.count
        func names(_ list: [FantasyPlayer]) -> String { list.map(\.name).joined(separator: ", ") }
        return [
            hurt.isEmpty ? nil : "\(hurt.count) out (\(names(hurt)))",
            questionable.isEmpty ? nil : "\(questionable.count) questionable (\(names(questionable)))",
            bye.isEmpty ? nil : "\(bye.count) on bye (\(names(bye)))",
            "\(max(0, healthy)) healthy",
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var injuryReport: some View {
        let sorted = players.sorted {
            ($0.injury?.severity ?? (onBye($0) ? 0 : -1), $1.name) > ($1.injury?.severity ?? (onBye($1) ? 0 : -1), $0.name)
        }
        return SportsCard(title: "Injury Report") {
            Text("Every rostered player, most serious first.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, player in
                if index > 0 { Divider() }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(player.name).font(.subheadline.weight(.semibold))
                            Text([player.team, player.position].compactMap { $0 }.joined(separator: " - "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let detail = player.injury?.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if let news = base.news[player.id]?.first {
                            Text(news.headline).font(.caption).lineLimit(3)
                            Text("\(news.source) · \(news.published.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    StatusTag(injury: player.injury, onBye: onBye(player) && player.injury == nil)
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var latestNews: some View {
        let cutoff = Date.now.addingTimeInterval(-4 * 24 * 3600)
        let items = players.flatMap { player in (base.news[player.id] ?? []).filter { $0.published > cutoff }.map { (player, $0) } }
            .sorted { $0.1.published > $1.1.published }
        if !items.isEmpty {
            SportsCard(title: "Latest Roster News") {
                Text("The last few days of news on your players.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
                ForEach(Array(items.enumerated()), id: \.element.1.id) { index, item in
                    if index > 0 { Divider() }
                    StoryRow(player: item.0, news: item.1)
                    if let story = item.1.story {
                        Text(story).font(.caption).foregroundStyle(.secondary).lineLimit(4).padding(.bottom, 6)
                    }
                }
            }
        }
    }

    // MARK: Bye weeks

    private enum WeekStatus {
        case clear, covered, hole(Int)

        var title: String {
            switch self {
            case .clear: "Clear"
            case .covered: "Covered"
            case .hole(let count): "\(count) hole\(count == 1 ? "" : "s")"
            }
        }

        var color: Color {
            switch self {
            case .clear: .green
            case .covered: .yellow
            case .hole: .red
            }
        }
    }

    private struct WeekPlan: Identifiable {
        let week: Int
        let cover: LineupCover
        let teamsOnBye: [String]
        var id: Int { week }

        var status: WeekStatus {
            cover.holes > 0 ? .hole(cover.holes) : cover.changes.isEmpty ? .clear : .covered
        }

        /// Starters who can't play (and empty slots): "Josh Allen (QB)", "RB slot empty".
        var missing: [String] {
            cover.changes.compactMap { slot in
                guard let starter = slot.starter else { return "\(slot.label) slot empty" }
                // A starter who just moves to another slot isn't missing.
                return cover.slots.contains { $0.filledBy?.id == starter.id } ? nil : "\(starter.name) (\(slot.label))"
            }
        }

        /// Who fills each changed slot: "QB: Mahomes", or "DEF: pickup needed".
        var coveredBy: [(text: String, isHole: Bool)] {
            cover.changes.map { slot in
                (slot.filledBy.map { "\(slot.label): \($0.name)" } ?? "\(slot.label): pickup needed", slot.filledBy == nil)
            }
        }
    }

    /// Each week from now until the playoffs. Out: misses this week only; IR and the like: about four weeks;
    /// no team listed: no known bye, so available.
    /// shortcut: injured players' timelines come from status alone; news-based return dates would be better.
    private var plans: [WeekPlan] {
        let last = (base.calendar?.playoffWeekStart ?? 15) - 1
        guard base.upcomingWeek <= last else { return [] }
        return (base.upcomingWeek...last).map { week in
            let cover = LineupCover(lineup: base.team.lineup, bench: base.team.bench) { player in
                let severity = player.injury?.severity ?? 0
                if let team = player.team, base.byes[team] == week { return false }
                if severity >= 4 { return week >= base.upcomingWeek + 4 }
                return week != base.upcomingWeek || severity < 3
            }
            return WeekPlan(week: week, cover: cover, teamsOnBye: base.byes.filter { $0.value == week }.map(\.key).sorted())
        }
    }

    @ViewBuilder
    private var byeHoles: some View {
        let plans = plans
        if !plans.isEmpty {
            SportsCard(title: "Bye Weeks") {
                Text("Clear: nobody missing. Covered: your bench fills every gap. Hole: a slot needs a pickup. Outlined = trade-deadline week.")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(plans) { plan in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Wk \(plan.week)").font(.caption.weight(.semibold))
                            HStack(spacing: 4) {
                                Circle().fill(plan.status.color).frame(width: 7, height: 7)
                                Text(plan.status.title).font(.caption).foregroundStyle(plan.status.color)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(plan.status.color.opacity(0.08), in: .rect(cornerRadius: 10))
                        .overlay {
                            if plan.week == base.calendar?.tradeDeadlineWeek {
                                RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("Week"); Text("Status"); Text("Who’s missing")
                        Text("Covered by").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.vertical, 6)
                    ForEach(plans) { plan in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(plan.week)\(plan.week == base.calendar?.tradeDeadlineWeek ? " · Deadline" : "")").monospacedDigit()
                                if !plan.teamsOnBye.isEmpty {
                                    Text("Byes: " + plan.teamsOnBye.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            HStack(spacing: 4) {
                                Circle().fill(plan.status.color).frame(width: 7, height: 7)
                                Text(plan.status.title).foregroundStyle(plan.status.color)
                            }
                            Text(plan.missing.isEmpty ? "–" : plan.missing.joined(separator: "\n"))
                            VStack(alignment: .leading, spacing: 2) {
                                if plan.coveredBy.isEmpty { Text("–").foregroundStyle(.secondary) }
                                ForEach(plan.coveredBy.indices, id: \.self) { index in
                                    let line = plan.coveredBy[index]
                                    Text(line.text).foregroundStyle(line.isHole ? .red : .primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }
}
