import SportsKit
import SwiftUI

/// Compact score row in the iOS Sports style: away over home, status on the right.
struct GameRow: View {
    let game: Game
    /// Fixed so scores line up down a list; nil sizes the status to its text (single cards, e.g. the menu bar).
    var statusWidth: CGFloat? = 96

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                teamLine(game.away)
                teamLine(game.home)
            }
            GameStatus(game: game)
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(width: statusWidth, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.accessibilitySummary)
    }

    private func teamLine(_ competitor: Game.Competitor) -> some View {
        HStack(spacing: 8) {
            TeamLogo(team: competitor.team)
            Text(competitor.team.abbreviation)
                .font(.headline)
                .fixedSize()
            // Gives way first when space is tight.
            Text(competitor.team.shortName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let record = competitor.record {
                Text(record)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if let score = competitor.score {
                Text(score, format: .number)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .foregroundStyle(game.isLosing(competitor) ? .secondary : .primary)
    }
}
