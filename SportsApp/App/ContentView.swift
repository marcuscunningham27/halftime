import SportsKit
import SwiftData
import SwiftUI

struct ContentView: View {
    enum SidebarItem: Hashable {
        case home
        case fantasy
        case league(League.ID)
        case team(leagueID: League.ID, teamID: Team.ID)
    }

    let provider: any SportsProvider

    @State private var leagues: [League] = []
    @State private var selection: SidebarItem? = .home
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Bumped when a sidebar row is clicked; pages watch it to return to their top level (out of an open game).
    @State private var popToRoot = 0
    /// Every team, from each league's standings, loaded the first time someone searches.
    @State private var allTeams: [(league: League, team: Team)] = []
    @Query(sort: \FollowedLeague.createdAt) private var followedLeagues: [FollowedLeague]
    @Query(sort: \FollowedTeam.createdAt) private var followedTeams: [FollowedTeam]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Home", systemImage: "house")
                    .tag(SidebarItem.home)
                    .onReselect { popToRoot += 1 }
                Label("Fantasy", systemImage: "football")
                    .tag(SidebarItem.fantasy)
                    .onReselect { popToRoot += 1 }
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    browsing
                } else {
                    searchResults
                }
            }
            .scrollContentBackground(.hidden)
            // The hairline in the gap above followed teams, drawn by the list since rows clip anything outside them.
            .overlayPreferenceValue(FirstTeamRow.self) { anchor in
                GeometryReader { geometry in
                    if let anchor {
                        let row = geometry[anchor]
                        Rectangle().fill(.separator).frame(width: geometry.size.width - 32, height: 1)
                            .position(x: geometry.size.width / 2, y: row.minY - 10)
                    }
                }
                .allowsHitTesting(false)
            }
            // Keeps the selected Home row clear of the glass panel's rounded top edge.
            .padding(.top, 8)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .padding(8)
        } detail: {
            detail.environment(\.popToRoot, popToRoot)
        }
        // Leaving for another page clears the search and gives the keyboard back.
        .onChange(of: selection) {
            query = ""
            searchFocused = false
        }
        .task {
            leagues = (try? await provider.leagues()) ?? []
        }
        .onAppear { MenuBarMode.windowOpened() }
        .onDisappear { MenuBarMode.windowClosed() }
    }

    /// Followed leagues, a separator, followed teams, then every league.
    @ViewBuilder
    private var browsing: some View {
        Section("Following") {
            if followedLeagues.isEmpty && followedTeams.isEmpty {
                Text("Nothing followed yet")
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            ForEach(followedLeagues) { followed in
                if let league = league(followed.leagueID) {
                    Label { Text(league.abbreviation) } icon: { LeagueLogo(league: league, size: 18) }
                        .tag(SidebarItem.league(league.id))
                        .onReselect { popToRoot += 1 }
                        .contextMenu { FollowLeagueButton(league: league) }
                }
            }
        }
        // Teams in their own headerless section: the gap between sections belongs to no row, so no selection covers it.
        Section {
            ForEach(followedTeams) { followed in
                Label {
                    Text(followed.displayName)
                } icon: {
                    TeamLogo(team: followed.team, size: 18)
                }
                .tag(SidebarItem.team(leagueID: followed.leagueID, teamID: followed.teamID))
                .onReselect { popToRoot += 1 }
                .contextMenu { FollowTeamButton(team: followed.team, leagueID: followed.leagueID) }
                .anchorPreference(key: FirstTeamRow.self, value: .bounds) {
                    followed.id == followedTeams.first?.id && !followedLeagues.isEmpty ? $0 : nil
                }
            }
        }
        Section("Leagues") {
            ForEach(leagues) { league in
                Label { Text(league.abbreviation) } icon: { LeagueLogo(league: league, size: 18) }
                    .tag(SidebarItem.league(league.id))
                    .onReselect { popToRoot += 1 }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search teams and leagues", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .padding(.vertical, 4)
        .selectionDisabled()
        .task(id: query.isEmpty) {
            guard !query.isEmpty, allTeams.isEmpty else { return }
            let leagues = leagues, provider = provider
            allTeams = await withTaskGroup(of: [(league: League, team: Team)].self) { group in
                for league in leagues {
                    group.addTask {
                        let standings = try? await provider.standings(league: league)
                        return standings?.groups.flatMap(\.entries).map { (league, $0.team) } ?? []
                    }
                }
                var all: [(league: League, team: Team)] = []
                for await teams in group { all += teams }
                return all.sorted { $0.team.displayName < $1.team.displayName }
            }
        }
    }

    /// Leagues and teams whose names match, each with a star to follow it.
    @ViewBuilder
    private var searchResults: some View {
        let text = query.trimmingCharacters(in: .whitespaces)
        let matchingLeagues = leagues.filter {
            $0.name.localizedStandardContains(text) || $0.abbreviation.localizedStandardContains(text)
        }
        let matchingTeams = allTeams.filter {
            $0.team.displayName.localizedStandardContains(text)
                || $0.team.abbreviation.localizedCaseInsensitiveCompare(text) == .orderedSame
        }
        if !matchingLeagues.isEmpty {
            Section("Leagues") {
                ForEach(matchingLeagues) { league in
                    HStack {
                        Label { Text(league.name).lineLimit(1) } icon: { LeagueLogo(league: league, size: 18) }
                        Spacer()
                        FollowLeagueButton(league: league).labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                    .tag(SidebarItem.league(league.id))
                }
            }
        }
        Section("Teams") {
            if matchingTeams.isEmpty {
                Text(allTeams.isEmpty ? "Loading teams…" : "No matching teams")
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            ForEach(matchingTeams, id: \.team.id) { match in
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(match.team.displayName).lineLimit(1)
                            Text(match.league.abbreviation).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { TeamLogo(team: match.team, size: 18) }
                    Spacer()
                    FollowTeamButton(team: match.team, leagueID: match.league.id).labelStyle(.iconOnly).buttonStyle(.plain)
                }
                .selectionDisabled()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            if leagues.isEmpty {
                placeholder
            } else {
                HomeView(provider: provider, leagues: leagues) { selection = .league($0.id) }
            }
        case .fantasy:
            FantasyView(provider: provider)
        case .league(let id):
            if let league = league(id) {
                ScoreboardView(provider: provider, league: league)
                    .id(selection)
            } else {
                placeholder
            }
        case .team(let leagueID, let teamID):
            if let league = league(leagueID),
               let followed = followedTeams.first(where: { $0.leagueID == leagueID && $0.teamID == teamID }) {
                ScoreboardView(provider: provider, league: league, team: followed.team)
                    .id(selection)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("Select a League", systemImage: "sportscourt")
    }

    private func league(_ id: League.ID) -> League? {
        leagues.first { $0.id == id }
    }
}

/// Where the first followed team row is, so the sidebar can draw the separator above it.
private struct FirstTeamRow: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

extension EnvironmentValues {
    /// Changes when the page's sidebar row is clicked again; navigation stacks pop back to their root.
    @Entry var popToRoot = 0
}

private extension View {
    /// Runs alongside the row's own selection, so a click on the row that's already selected still registers.
    /// Stretched across the row, so a click anywhere on it counts, not just on the label.
    func onReselect(_ action: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded(action))
    }
}
