import Foundation
import Security
import SportsKit

/// The fantasy leagues saved in Settings, across providers, and which one the Fantasy page shows.
/// League references live in UserDefaults; ESPN's private-league cookies live in the Keychain.
@MainActor @Observable
final class FantasyStore {
    static let shared = FantasyStore()

    private static let leaguesKey = "fantasyLeagues"
    private static let activeKey = "fantasyActiveLeague"

    private(set) var leagues: [FantasyLeagueRef] = []
    var activeID: String? {
        didSet { UserDefaults.standard.set(activeID, forKey: Self.activeKey) }
    }

    var active: FantasyLeagueRef? { leagues.first { $0.id == activeID } ?? leagues.first }

    /// Your players across every saved league, for marking them on NFL game pages.
    private(set) var roster = FantasyRoster(players: [])
    private var rosterLoaded: Date?

    /// Loads every league's team, at most every 10 minutes; a league that fails is just left out.
    func loadRoster() async {
        if let rosterLoaded, rosterLoaded.timeIntervalSinceNow > -600 { return }
        rosterLoaded = .now
        guard !leagues.isEmpty, let state = try? await Sleeper.state() else { return }
        var players: [FantasyPlayer] = []
        for league in leagues where league.provider != .yahoo {
            let credentials = league.provider == .espn ? credentials(leagueID: league.leagueID) : nil
            if let team = try? await FantasyData.team(for: league, season: state.season, espnCredentials: credentials,
                                                      playersCache: FantasyView.playersCache) {
                players += team.players.filter { new in !players.contains { $0.id == new.id } }
            }
        }
        roster = FantasyRoster(players: players)
    }

    private init() {
        let defaults = UserDefaults.standard
        leagues = defaults.data(forKey: Self.leaguesKey).flatMap { try? JSONDecoder().decode([FantasyLeagueRef].self, from: $0) } ?? []
        activeID = defaults.string(forKey: Self.activeKey)
        // The first Fantasy version kept one Sleeper league under its own keys; carry it over once.
        if leagues.isEmpty, let user = defaults.string(forKey: "sleeperUserID"), let league = defaults.string(forKey: "sleeperLeagueID"),
           !user.isEmpty, !league.isEmpty {
            add([FantasyLeagueRef(provider: .sleeper, leagueID: league, name: defaults.string(forKey: "sleeperLeagueName") ?? "Sleeper League",
                                  memberID: user)])
        }
    }

    /// Adds leagues (replacing any saved under the same ID); the first one added becomes active if none is.
    func add(_ new: [FantasyLeagueRef]) {
        leagues = leagues.filter { old in !new.contains { $0.id == old.id } } + new
        rosterLoaded = nil
        if active == nil || activeID == nil { activeID = new.first?.id }
        save()
    }

    func remove(_ league: FantasyLeagueRef) {
        leagues.removeAll { $0.id == league.id }
        rosterLoaded = nil
        if league.provider == .espn { setCredentials(nil, leagueID: league.leagueID) }
        if activeID == league.id { activeID = leagues.first?.id }
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(leagues), forKey: Self.leaguesKey)
    }

    // MARK: ESPN cookies

    private static func query(_ leagueID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.marcuscunningham.SportsApp.espnFantasy",
         kSecAttrAccount as String: leagueID]
    }

    func credentials(leagueID: String) -> ESPNFantasy.Credentials? {
        var query = Self.query(leagueID)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ESPNFantasy.Credentials.self, from: data)
    }

    /// Saves (or with nil, deletes) a private league's cookies. Returns false if the Keychain refused.
    @discardableResult
    func setCredentials(_ credentials: ESPNFantasy.Credentials?, leagueID: String) -> Bool {
        SecItemDelete(Self.query(leagueID) as CFDictionary)
        guard let credentials, let data = try? JSONEncoder().encode(credentials) else { return true }
        var item = Self.query(leagueID)
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
