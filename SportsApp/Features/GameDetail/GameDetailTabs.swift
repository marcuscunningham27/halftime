import SportsKit
import SwiftUI

/// Drives for NFL (All Drives / Scoring Drives), or plays by period for other sports; newest first.
struct PlayByPlayView: View {
    let provider: any SportsProvider
    let game: Game
    let detail: GameDetail

    @State private var scoringOnly = false

    var body: some View {
        if detail.plays.isEmpty {
            ContentUnavailableView("No Plays Yet", systemImage: "list.bullet")
        } else {
            VStack(spacing: 14) {
                ProbabilityView(provider: provider, game: game, detail: detail)
                GlassPicker(selection: $scoringOnly, options: [
                    (false, detail.drives.isEmpty ? "All Plays" : "All Drives"),
                    (true, detail.drives.isEmpty ? "Scoring Plays" : "Scoring Drives"),
                ])

                if detail.drives.isEmpty {
                    periods
                } else {
                    drives
                }
            }
        }
    }

    private var drives: some View {
        let shown = detail.drives.filter { !scoringOnly || $0.isScore }.reversed()
        let latestID = detail.drives.last?.id
        return LazyVStack(spacing: 12) {
            ForEach(Array(shown)) { drive in
                let team = team(drive.teamID)
                SportsCard {
                    HStack(spacing: 8) {
                        if let team { TeamLogo(team: team, size: 20) }
                        Text(drive.summary.capitalized).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if let result = drive.result, !result.isEmpty {
                            Text(result).font(.subheadline.weight(.semibold))
                                .foregroundStyle(drive.isScore ? .primary : .secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    ForEach(drive.plays.reversed()) { play in
                        Divider()
                        PlayRow(play: play, color: team?.color ?? .accentColor, fantasy: game.fantasyPlayers(in: play))
                    }
                }
                // The drive in progress gets the offence's colour down its edge, as on iOS.
                .overlay(alignment: .leading) {
                    if game.status == .live, drive.id == latestID, let team {
                        Capsule().fill(team.color).frame(width: 3).padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private var periods: some View {
        let plays = detail.plays.filter { !scoringOnly || $0.isScoring }
        let numbers = Array(Set(plays.map(\.period))).sorted(by: >)
        return LazyVStack(spacing: 12) {
            ForEach(numbers, id: \.self) { period in
                SportsCard(title: game.league.periodTitle(period)) {
                    ForEach(plays.filter { $0.period == period }.reversed()) { play in
                        Divider()
                        PlayRow(play: play, color: team(play.teamID)?.color ?? .accentColor,
                                logo: team(play.teamID), score: play.isScoring ? scoreText(play) : nil,
                                fantasy: game.fantasyPlayers(in: play))
                    }
                }
            }
        }
    }

    private func team(_ id: Team.ID?) -> Team? {
        [game.away.team, game.home.team].first { $0.id == id }
    }

    private func scoreText(_ play: Play) -> String? {
        guard let away = play.awayScore, let home = play.homeScore else { return nil }
        return "\(game.away.team.abbreviation) \(away) – \(home) \(game.home.team.abbreviation)"
    }
}

/// iOS-style play: bold headline, description, then "clock · down & distance at spot" with the spot in team colour.
struct PlayRow: View {
    let play: Play
    let color: Color
    var logo: Team?
    var score: String?
    /// Your fantasy players in this play, starred and highlighted.
    var fantasy: [FantasyPlayer] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let logo { TeamLogo(team: logo, size: 20).padding(.top, 2) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let type = play.type, !type.isEmpty {
                        Text(type).font(.headline)
                    }
                    ForEach(fantasy, id: \.id) { player in
                        FantasyBadge()
                        Text(player.name).font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    }
                }
                Text(play.text)
                    .foregroundStyle(play.type == nil ? .primary : .secondary)
                    .fontWeight(play.isScoring ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
                footer.font(.subheadline)
            }
            Spacer(minLength: 0)
            if let score {
                Text(score).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .fantasyHighlight(!fantasy.isEmpty)
        .padding(.horizontal, -6)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Group {
            if let spot = play.spot, let at = spot.range(of: " at ") {
                let place = Text(spot[at.upperBound...]).foregroundStyle(color)
                Text("\(play.clock.isEmpty ? "" : play.clock + " · ")\(String(spot[..<at.lowerBound])) at \(place)")
            } else if let spot = play.spot {
                Text([play.clock, spot].filter { !$0.isEmpty }.joined(separator: " · "))
            } else {
                Text(play.clock)
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// Game leaders, then player stat tables, away team first.
struct BoxScoreView: View {
    let game: Game
    let boxScores: [BoxScore]
    var leaders: [GameOverview.Leader] = []

    var body: some View {
        if boxScores.isEmpty && leaders.isEmpty {
            ContentUnavailableView("No Box Score Yet", systemImage: "tablecells")
        } else {
            VStack(spacing: 12) {
                GameLeadersView(game: game, leaders: leaders)
                ForEach(boxScores.filter { $0.teamID == game.away.team.id } + boxScores.filter { $0.teamID == game.home.team.id }) { box in
                    SportsCard(title: box.title) {
                        ScrollView(.horizontal) {
                            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
                                GridRow {
                                    Text("Player").gridColumnAlignment(.leading)
                                    ForEach(Array(box.labels.enumerated()), id: \.offset) { Text($0.element) }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Divider()
                                ForEach(box.rows) { row in
                                    let yours = game.leagueID == League.nfl.id
                                        && FantasyStore.shared.roster.contains(athleteID: row.id, name: row.name)
                                    GridRow {
                                        HStack(spacing: 4) {
                                            Text(row.name)
                                            if yours { FantasyBadge() }
                                        }
                                        .foregroundStyle(yours ? .yellow : .primary)
                                        ForEach(Array(row.stats.enumerated()), id: \.offset) { Text($0.element) }
                                    }
                                }
                            }
                            .monospacedDigit()
                            .padding(.vertical, 6)
                        }
                        .scrollIndicators(.never)
                        if let key = box.key {
                            Text(key).font(.caption2).foregroundStyle(.secondary).padding(.bottom, 4)
                        }
                    }
                }
            }
        }
    }
}

/// iOS-style team stats: big values either side, label in the middle, comparison bars underneath.
struct TeamStatsView: View {
    let game: Game
    let stats: [TeamStat]

    var body: some View {
        if stats.isEmpty {
            ContentUnavailableView("No Team Stats Yet", systemImage: "chart.bar")
        } else {
            SportsCard {
                HStack {
                    TeamLogo(team: game.away.team, size: 22)
                    Spacer()
                    Text("Team Stats").font(.headline)
                    Spacer()
                    TeamLogo(team: game.home.team, size: 22)
                }
                .padding(.bottom, 8)
                ForEach(stats) { stat in
                    StatRow(stat: stat, awayColor: game.away.team.color, homeColor: game.home.team.color)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stat.label): \(game.away.team.shortName) \(stat.away), \(game.home.team.shortName) \(stat.home)")
                }
            }
        }
    }
}

private struct StatRow: View {
    let stat: TeamStat
    let awayColor: Color
    let homeColor: Color

    var body: some View {
        let away = Self.number(stat.away), home = Self.number(stat.home)
        let total = away + home
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.away).font(.score(28)).monospacedDigit()
                Spacer()
                Text(stat.label).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
                Text(stat.home).font(.score(28)).monospacedDigit()
            }
            // Bars split by share; the leader's is brighter.
            GeometryReader { geometry in
                let gap: CGFloat = 6, width = geometry.size.width - gap
                let awayShare = total > 0 ? away / total : 0.5
                HStack(spacing: gap) {
                    Capsule().fill(awayColor.opacity(away >= home ? 1 : 0.45)).frame(width: width * awayShare)
                    Capsule().fill(homeColor.opacity(home >= away ? 1 : 0.45))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 7)
    }

    /// Reads "306", "5.6", "2/10" or "5-16" (as made of attempted), and "29:34" (as minutes).
    static func number(_ text: String) -> Double {
        if text.contains(":") {
            let parts = text.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 ? parts[0] + parts[1] / 60 : 0
        }
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Double($0) }
        if text.contains("%") { return Double(text.filter { $0.isNumber || $0 == "." }) ?? 0 }
        return parts.first ?? 0
    }
}
