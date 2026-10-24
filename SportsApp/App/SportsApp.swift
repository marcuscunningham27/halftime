import ServiceManagement
import SportsKit
import SwiftData
import SwiftUI

@main
struct SportsApp: App {
    private let provider: ESPNProvider
    private let container: ModelContainer
    private let notifications: NotificationService
    /// Today's games for followed leagues, behind the menu bar item; polls for as long as the app runs.
    @State private var liveScores: ScoreboardPoller

    init() {
        // Room for every league's scoreboards (about 100 KB a day each) and game details, kept on disk
        // so the next launch can draw last time's scores before the network answers.
        URLCache.shared = URLCache(memoryCapacity: 20_000_000, diskCapacity: 200_000_000)
        let provider = ESPNProvider()
        self.provider = provider
        do {
            container = try ModelContainer(for: Schema(sportsModels))
        } catch {
            // Without the store, follows can't be read or saved; failing loudly beats silently dropping them.
            fatalError("Couldn’t open the Sports data store: \(error)")
        }
        #if !DEBUG
        // SPEC: launch at login by default, since alerts need the app running. Once only, so turning it off sticks.
        // Release only, so development builds in DerivedData don't land in Login Items.
        if !UserDefaults.standard.bool(forKey: "didOfferLaunchAtLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didOfferLaunchAtLogin")
        }
        #endif
        let notifications = NotificationService(container: container, provider: provider)
        self.notifications = notifications
        // MenuBarLabel sets the leagues from what's followed; this poller alone drives notifications.
        let liveScores = ScoreboardPoller(provider: provider, leagues: [])
        liveScores.onUpdate = { notifications.process(old: $0, new: $1) }
        _liveScores = State(initialValue: liveScores)
    }

    var body: some Scene {
        // A single Window, so Open Sports brings it forward instead of opening another.
        Window("Sports", id: "main") {
            ContentView(provider: provider)
        }
        // Widget taps send sportsapp://open; this opens the window if it was closed, or brings it forward.
        .handlesExternalEvents(matching: ["sportsapp://open"])
        .defaultSize(width: 1000, height: 700)
        .modelContainer(container)

        MenuBarExtra {
            MenuBarPopover(scores: liveScores)
                .modelContainer(container)
        } label: {
            MenuBarLabel(scores: liveScores)
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
