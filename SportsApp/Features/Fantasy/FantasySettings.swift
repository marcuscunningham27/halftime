import SportsKit
import SwiftUI

/// Settings › Fantasy: the leagues you've saved, across apps, and a way to add more from each provider.
struct FantasySettings: View {
    @State private var provider = FantasyProvider.sleeper
    private var store: FantasyStore { .shared }

    var body: some View {
        Form {
            Section {
                if store.leagues.isEmpty {
                    Text("No leagues yet. Add one below.").foregroundStyle(.secondary)
                }
                ForEach(store.leagues) { league in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(league.name)
                            Text(league.provider.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle", role: .destructive) { store.remove(league) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Your Leagues")
            } footer: {
                Text("Switch between them from the league name at the top of the Fantasy page.")
            }
            Section("Add Leagues") {
                Picker("App", selection: $provider) {
                    ForEach(FantasyProvider.allCases) { Text($0.title).tag($0) }
                }
                switch provider {
                case .sleeper: SleeperAdder()
                case .espn: ESPNAdder()
                case .yahoo:
                    Text("Yahoo Fantasy only lets apps in through a Yahoo sign-in tied to a registered Yahoo developer app, which Halftime doesn’t have yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Sleeper: a username finds every NFL league that user is in this season; add any of them.
private struct SleeperAdder: View {
    @AppStorage("sleeperUsername") private var username = ""
    @State private var draft = ""
    @State private var userID: String?
    @State private var found: [Sleeper.FantasyLeague] = []
    @State private var error: String?
    @State private var isLoading = false
    private var store: FantasyStore { .shared }

    var body: some View {
        HStack {
            TextField("Sleeper username", text: $draft, prompt: Text("username")).onSubmit(find)
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button("Find Leagues", action: find).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task { if draft.isEmpty { draft = username } }
        if let error {
            Text(error).foregroundStyle(.red)
        }
        if let userID {
            ForEach(found) { league in
                let ref = FantasyLeagueRef(provider: .sleeper, leagueID: league.id, name: league.name, memberID: userID)
                HStack {
                    Text(league.name)
                    Spacer()
                    if store.leagues.contains(where: { $0.id == ref.id }) {
                        Label("Added", systemImage: "checkmark").foregroundStyle(.secondary)
                    } else {
                        Button("Add") { store.add([ref]) }
                    }
                }
            }
        }
    }

    private func find() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                guard let id = try await Sleeper.userID(username: name) else {
                    error = "No Sleeper user named “\(name)”."
                    return
                }
                username = name
                let state = try await Sleeper.state()
                found = try await Sleeper.leagues(userID: id, season: state.season)
                userID = id
                error = found.isEmpty ? "No NFL leagues this season for this user." : nil
            } catch {
                self.error = "Couldn’t reach Sleeper. \(error.localizedDescription)"
            }
        }
    }
}

/// ESPN: a league ID (from the league's web address), cookies for private leagues, then which team is yours.
private struct ESPNAdder: View {
    @State private var leagueID = ""
    @State private var espnS2 = ""
    @State private var swid = ""
    @State private var info: ESPNFantasy.LeagueInfo?
    @State private var teamID = ""
    @State private var error: String?
    @State private var isLoading = false
    private var store: FantasyStore { .shared }

    private var credentials: ESPNFantasy.Credentials? {
        espnS2.isEmpty || swid.isEmpty ? nil : ESPNFantasy.Credentials(espnS2: espnS2, swid: swid)
    }

    var body: some View {
        TextField("League ID", text: $leagueID, prompt: Text("from fantasy.espn.com/…?leagueId=123456"))
        SecureField("espn_s2 (private leagues)", text: $espnS2)
        SecureField("SWID (private leagues)", text: $swid)
        HStack {
            Text("For a private league, copy the espn_s2 and SWID cookies from your browser while signed in to ESPN. They’re kept in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button("Find League", action: find).disabled(Int(leagueID.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
        if let error {
            Text(error).foregroundStyle(.red)
        }
        if let info {
            Picker("Your team in \(info.name)", selection: $teamID) {
                ForEach(info.teams, id: \.id) { Text($0.name).tag($0.id) }
            }
            Button("Add League") {
                let id = leagueID.trimmingCharacters(in: .whitespaces)
                if let credentials, !store.setCredentials(credentials, leagueID: id) {
                    error = "The Keychain couldn’t save the cookies."
                    return
                }
                store.add([FantasyLeagueRef(provider: .espn, leagueID: id, name: info.name, memberID: teamID)])
                self.info = nil
                leagueID = ""; espnS2 = ""; swid = ""
            }
            .disabled(teamID.isEmpty)
        }
    }

    private func find() {
        let id = leagueID.trimmingCharacters(in: .whitespaces)
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let state = try await Sleeper.state() // NFL season, same for every provider
                let found = try await ESPNFantasy.league(leagueID: id, season: state.season, credentials: credentials)
                info = found
                teamID = found.teams.first?.id ?? ""
                error = nil
            } catch {
                info = nil
                self.error = error.localizedDescription
            }
        }
    }
}
