import SportsKit
import SwiftData
import SwiftUI

/// Today's live and upcoming games for what you follow, as glass score cards, plus a way into the main window.
struct MenuBarPopover: View {
    let scores: ScoreboardPoller

    @Environment(\.openWindow) private var openWindow
    @Query private var followedLeagues: [FollowedLeague]
    @Query private var followedTeams: [FollowedTeam]

    var body: some View {
        let follows = Follows(leagues: followedLeagues, teams: followedTeams)
        let games = scores.games.filter { $0.status != .final && follows.includes($0) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
            if follows.isEmpty {
                ContentUnavailableView("Nothing Followed Yet", systemImage: "star",
                                       description: Text("Star a team or league in Halftime to see its games here."))
                    .frame(height: 180)
            } else if games.isEmpty {
                ContentUnavailableView("No Live or Upcoming Games", systemImage: "sportscourt")
                    .frame(height: 160)
            } else {
                ScrollView {
                    GlassEffectContainer {
                        VStack(spacing: 8) {
                            ForEach(games) { game in
                                GameRow(game: game, statusWidth: nil)
                                    .padding(.horizontal, 12)
                                    .glassEffect(in: .rect(cornerRadius: 14))
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // As tall as the cards, up to a cap; only then does it scroll.
                .frame(maxHeight: 432)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(action: openMainWindow) {
                    Label("Open Halftime", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                // Same cooperative-activation problem as Open Sports.
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 360)
    }

    /// Raises the existing window, or opens it if it was closed.
    private func openMainWindow() {
        MenuBarMode.windowOpened()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" && ($0.isVisible || $0.isMiniaturized) }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        // The menu bar panel never makes the app active, so the cooperative NSApp.activate() is declined
        // and the window stays behind other apps; the deprecated forced form still works.
        NSApp.activate(ignoringOtherApps: true)
    }
}
