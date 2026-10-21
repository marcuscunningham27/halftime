import SportsKit
import SwiftUI

/// Score cards stacked with dividers; each opens the game. Shared by Home and league pages.
struct GameCardRows: View {
    let games: [Game]
    var followed: Set<Follows.TeamRef> = []
    var showsDate = false

    var body: some View {
        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
            if index > 0 { Divider() }
            NavigationLink(value: game.id) {
                ScoreCard(game: game, followed: followed, showsDate: showsDate)
            }
            .buttonStyle(.plain)
            .contextMenu {
                FollowTeamButton(team: game.away.team, leagueID: game.leagueID)
                FollowTeamButton(team: game.home.team, leagueID: game.leagueID)
            }
        }
    }
}

/// A card section header like iOS: icon, title, chevron; tappable when it leads somewhere.
struct SectionHeader<Icon: View>: View {
    let title: String
    var action: (() -> Void)?
    @ViewBuilder let icon: Icon

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                icon
                Text(title).font(.headline)
                if action != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .padding(.top, 10)
    }
}

/// League table in cards, one per conference or division, followed teams starred.
struct StandingsView: View {
    let provider: any SportsProvider
    let league: League
    var followed: Set<Follows.TeamRef> = []

    @State private var standings: Standings?
    @State private var error: Error?

    var body: some View {
        Group {
            if let standings {
                ForEach(standings.groups) { group in
                    SportsCard(title: group.name) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("").gridCellColumns(3)
                                ForEach(standings.columns, id: \.self) { Text($0).gridColumnAlignment(.trailing) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                GridRow {
                                    Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                                    TeamLogo(team: entry.team, size: 22)
                                    HStack(spacing: 4) {
                                        Text(entry.team.shortName).lineLimit(1)
                                        if followed.contains(.init(leagueID: league.id, teamID: entry.team.id)) {
                                            Image(systemName: "star.fill").font(.caption2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    ForEach(Array(entry.values.enumerated()), id: \.offset) { Text($0.element).monospacedDigit() }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if let error {
                Text("Standings unavailable: \(error.localizedDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                // Also gives .task a view to hang on; an empty Group never appears, so it would never load.
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
        .task(id: league.id) {
            do {
                standings = try await provider.standings(league: league)
            } catch {
                self.error = error
            }
        }
    }
}
