import SportsKit
import SwiftUI

/// iOS Sports-style game page: team-coloured backdrop, big compressed scores, field position for NFL,
/// line score, then Stats, Play-By-Play and Box Score. `game` comes from the scoreboard, which keeps
/// it fresh; this view only loads the detail below the header.
struct GameDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", stats = "Stats", plays = "Play-By-Play", boxScore = "Box Score"
        var id: Self { self }
    }

    let provider: any SportsProvider
    let game: Game

    @State private var detail: GameDetail?
    @State private var error: Error?
    @State private var tab: Tab

    init(provider: any SportsProvider, game: Game) {
        self.provider = provider
        self.game = game
        // Before kickoff there are no stats yet, so start on the overview.
        _tab = State(initialValue: game.status == .scheduled ? .overview : .stats)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                GameHeader(game: game, detail: detail)
                    .padding(.bottom, 12) // breathing room before the tabs
                if let detail {
                    RecapCard(game: game, detail: detail).id(game.id)
                    AskCard(game: game, detail: detail).id(game.id)
                }
                GlassPicker(selection: $tab)
                content
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .backdrop(game.home.team.color)
        // The iOS app's game pages are always dark over the team colour.
        .environment(\.colorScheme, .dark)
        .navigationTitle("\(game.away.team.abbreviation) @ \(game.home.team.abbreviation)")
        .task {
            if game.leagueID == League.nfl.id { await FantasyStore.shared.loadRoster() }
        }
        // Restarts when the game goes live or ends; polls only while live.
        .task(id: game.status) {
            repeat {
                await load()
                guard game.status == .live else { return }
            } while (try? await Task.sleep(for: .seconds(15))) != nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let detail {
            switch tab {
            case .overview: GameOverviewView(game: game, overview: detail.overview)
            case .stats: TeamStatsView(game: game, stats: detail.teamStats)
            case .plays: PlayByPlayView(provider: provider, game: game, detail: detail)
            case .boxScore: BoxScoreView(game: game, boxScores: detail.boxScores, leaders: detail.overview.leaders)
            }
        } else if let error {
            ContentUnavailableView {
                Label("Couldn’t Load Game", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.glass)
            }
        } else {
            ProgressView().padding()
        }
    }

    private func load() async {
        do {
            detail = try await provider.gameDetail(for: game)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}

struct GameHeader: View {
    let game: Game
    var detail: GameDetail?

    var body: some View {
        VStack(spacing: 18) {
            Text(game.note ?? game.league.abbreviation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                side(game.away)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        if game.status == .live { Circle().fill(.red).frame(width: 7, height: 7) }
                        Text(game.headlineStatus).font(.headline).monospacedDigit()
                    }
                    if game.status == .scheduled {
                        Text(game.startDate, format: .dateTime.weekday(.wide).month().day())
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if let series = game.seriesSummary {
                        Text(series).font(.caption).foregroundStyle(.secondary)
                    }
                    // The Gamecast sports keep the line score between the teams, under the clock.
                    if lineScoreInHeader {
                        LineScore(game: game, compact: true).padding(.top, 14)
                    }
                }
                .padding(.top, 26)
                .frame(maxWidth: .infinity)
                side(game.home)
            }
            .frame(maxWidth: 600)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(game.accessibilitySummary)

            PlaySurfaceView(game: game, detail: detail)
                .padding(.bottom, 14) // keep the surface clear of the line score
            if game.status != .scheduled, !lineScoreInHeader {
                LineScore(game: game)
            }
        }
    }

    private var lineScoreInHeader: Bool { [League.nba.id, League.nfl.id, League.nhl.id, League.mlb.id].contains(game.leagueID) && game.status != .scheduled }

    private enum Direction { case left, right }

    private func winnerMark(pointing direction: Direction) -> some View {
        Image(systemName: direction == .right ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
            .font(.system(size: 12))
            .accessibilityLabel("Winner")
    }

    private func side(_ competitor: Game.Competitor) -> some View {
        VStack(spacing: 8) {
            let home = competitor.team.id == game.home.team.id
            // ESPN marks the winner with a small triangle pointing at its score, on the inside.
            let won = game.status == .final && !game.isLosing(competitor)
                && competitor.score != (home ? game.away.score : game.home.score)
            HStack(spacing: 6) {
                if won, home { winnerMark(pointing: .right) }
                Text(competitor.score.map(String.init) ?? "–")
                    .font(.score(72))
                    .monospacedDigit()
                    .foregroundStyle(game.isLosing(competitor) ? .secondary : .primary)
                if won, !home { winnerMark(pointing: .left) }
                if game.hasBall(competitor) {
                    Image(systemName: "football.fill").font(.callout).foregroundStyle(.secondary)
                }
            }
            TeamLogo(team: competitor.team, size: 48)
            HStack(spacing: 4) {
                Text(competitor.team.shortName).font(.headline)
                FollowTeamButton(team: competitor.team, leagueID: game.leagueID)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            if let record = competitor.record {
                Text(record).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(minWidth: 150)
    }
}

/// Full-width period-by-period table, every regulation period shown.
struct LineScore: View {
    let game: Game
    /// Smaller type and a narrower team column, for the header's centre column between the teams.
    var compact = false

    var body: some View {
        // Always show regulation, with dashes for periods not yet played.
        let periods = max(game.away.periodScores.count, game.home.periodScores.count, game.league.regulationPeriods)
        Grid(horizontalSpacing: 0, verticalSpacing: compact ? 5 : 7) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(1...periods, id: \.self) { Text(game.league.periodLabel($0)).frame(maxWidth: .infinity) }
                Text("T").frame(maxWidth: .infinity)
            }
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(.secondary)
            row(game.away, periods: periods)
            Divider().gridCellUnsizedAxes(.horizontal)
            row(game.home, periods: periods)
        }
        .font(compact ? .caption : .callout)
        .monospacedDigit()
        .frame(maxWidth: compact ? 320 : 480)
        // One sentence instead of a cell-by-cell grid.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("By \(game.league.periodStyle == .innings ? "inning" : "period"): "
            + [game.away, game.home].map { "\($0.team.shortName) \($0.periodScores.map(String.init).joined(separator: ", "))" }
                .joined(separator: "; "))
    }

    private func row(_ competitor: Game.Competitor, periods: Int) -> some View {
        GridRow {
            Text(competitor.team.abbreviation)
                .font((compact ? Font.caption : .callout).weight(.semibold))
                .frame(width: compact ? 34 : 48, alignment: .leading)
            ForEach(0..<periods, id: \.self) { index in
                Text(index < competitor.periodScores.count ? "\(competitor.periodScores[index])" : "–")
                    .frame(maxWidth: .infinity)
            }
            Text(competitor.score.map(String.init) ?? "–").fontWeight(.semibold).frame(maxWidth: .infinity)
        }
    }
}
