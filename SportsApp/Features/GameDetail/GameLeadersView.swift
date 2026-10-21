import SportsKit
import SwiftUI

/// ESPN-style leaders: headshot and big number each side, category in the middle, name, position and line below.
struct GameLeadersView: View {
    let game: Game
    let leaders: [GameOverview.Leader]

    var body: some View {
        let categories = Array(NSOrderedSet(array: leaders.map(\.category))).compactMap { $0 as? String }
        if !categories.isEmpty {
            SportsCard(title: game.status == .scheduled ? "Season Leaders" : "Game Leaders") {
                HStack {
                    TeamLogo(team: game.away.team, size: 26)
                    Text(game.away.team.abbreviation).font(.headline)
                    Spacer()
                    Text(game.home.team.abbreviation).font(.headline)
                    TeamLogo(team: game.home.team, size: 26)
                }
                .padding(.vertical, 8)
                ForEach(categories, id: \.self) { category in
                    Divider()
                    row(category).padding(.vertical, 10)
                }
            }
        }
    }

    private func row(_ category: String) -> some View {
        let away = leaders.first { $0.category == category && $0.teamID == game.away.team.id }
        let home = leaders.first { $0.category == category && $0.teamID == game.home.team.id }
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                headshot(away)
                Text(away?.mainValue ?? "").font(.score(30)).monospacedDigit()
                Spacer()
                Text(category)
                    .font(.scoreLabel())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 120)
                Spacer()
                Text(home?.mainValue ?? "").font(.score(30)).monospacedDigit()
                headshot(home)
            }
            HStack(alignment: .top) {
                caption(away, alignment: .leading)
                Spacer()
                caption(home, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category): " + [away, home].compactMap { $0.map { "\($0.athlete) \($0.line)" } }.joined(separator: "; "))
    }

    private func headshot(_ leader: GameOverview.Leader?) -> some View {
        AsyncImage(url: leader?.headshotURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.fill").font(.title2).foregroundStyle(.secondary)
        }
        .frame(width: 52, height: 52)
        .background(.white.opacity(0.12))
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.white.opacity(0.25)))
        .opacity(leader == nil ? 0 : 1)
    }

    @ViewBuilder
    private func caption(_ leader: GameOverview.Leader?, alignment: HorizontalAlignment) -> some View {
        if let leader {
            VStack(alignment: alignment, spacing: 1) {
                HStack(spacing: 4) {
                    Text(leader.shortName ?? leader.athlete).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let position = leader.position {
                        Text(position).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let summary = leader.summary, !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
