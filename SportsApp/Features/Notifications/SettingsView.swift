import ServiceManagement
import SportsKit
import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Notifications", systemImage: "bell.badge") { NotificationSettings() }
            Tab("Following", systemImage: "star") { FollowingSettings() }
            Tab("Fantasy", systemImage: "football") { FantasySettings() }
            Tab("Summaries", systemImage: "sparkles") { ClaudeSettings() }
        }
        .frame(width: 520, height: 560)
    }
}

/// Reads follows and overrides once per render so every toggle shows its resolved value.
private struct RulesReader<Content: View>: View {
    @ViewBuilder let content: (NotificationRules) -> Content

    @Query private var leagues: [FollowedLeague]
    @Query private var teams: [FollowedTeam]
    @Query private var preferences: [NotificationPreference]

    var body: some View {
        content(NotificationRules(leagues: leagues, teams: teams, preferences: preferences))
    }
}

/// One toggle per event that applies, showing the resolved value and writing an override at `scope`.
private struct EventToggles: View {
    let rules: NotificationRules
    let scope: PreferenceScope
    let leagueID: League.ID?

    @Environment(\.modelContext) private var context

    var body: some View {
        ForEach(NotificationEvent.allCases.filter { event in leagueID.flatMap(League.with).map(event.applies(to:)) ?? true }) { event in
            Toggle(event.title, isOn: Binding(
                get: { rules.resolved(event, at: scope) },
                set: { try? context.setPreference(event, at: scope, isEnabled: $0) }
            ))
        }
    }
}

struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    @AppStorage(MenuBarMode.closeToMenuKey) private var closeToMenu = false
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.regionDefault

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        do {
                            try enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if SMAppService.mainApp.status == .requiresApproval {
                    Text("Approve Sports in System Settings › General › Login Items.")
                } else {
                    Text("Alerts only arrive while Sports is running, so it stays in the menu bar.")
                }
            }
            Section {
                Toggle("Close to Menu", isOn: $closeToMenu)
            } footer: {
                Text("Closing the window leaves Sports in the menu bar only, with no Dock icon. Scores and alerts keep coming.")
            }
            Section {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("For weather at the venue. Field and court measurements stay in each sport’s own units.")
            }
        }
        .formStyle(.grouped)
    }
}

struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus?
    @AppStorage(NotificationService.QuietHoursKey.enabled) private var quietHours = false
    @AppStorage(NotificationService.QuietHoursKey.start) private var quietStart = NotificationService.QuietHoursKey.defaultStart
    @AppStorage(NotificationService.QuietHoursKey.end) private var quietEnd = NotificationService.QuietHoursKey.defaultEnd

    var body: some View {
        RulesReader { rules in
            Form {
                if status == .denied {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notifications are turned off for Sports").font(.headline)
                                Text("Allow them in System Settings to get alerts for the teams and leagues you follow.")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell.slash").foregroundStyle(.orange)
                        }
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!)
                        }
                    }
                }
                Section {
                    EventToggles(rules: rules, scope: .global, leagueID: nil)
                } header: {
                    Text("Alert me about")
                } footer: {
                    Text("These apply to everything you follow. Override them per league or team in Following.")
                }
                Section {
                    Toggle("Quiet hours", isOn: $quietHours)
                    if quietHours {
                        DatePicker("From", selection: time($quietStart), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: time($quietEnd), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Alerts during quiet hours are held until they end; you get the latest one per game.")
                }
            }
            .formStyle(.grouped)
        }
        .task {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    /// Bridges minutes-after-midnight storage to a time picker.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes.wrappedValue * 60)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = c.hour! * 60 + c.minute!
            }
        )
    }
}

/// Everything followed, collapsed to one row each with a star to unfollow; open a row for its alerts.
struct FollowingSettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FollowedLeague.createdAt) private var leagues: [FollowedLeague]
    @Query(sort: \FollowedTeam.createdAt) private var teams: [FollowedTeam]
    /// IDs of the rows opened to show their alert settings.
    @State private var expanded: Set<String> = []

    var body: some View {
        RulesReader { rules in
            Form {
                if leagues.isEmpty && teams.isEmpty {
                    ContentUnavailableView("Nothing Followed Yet", systemImage: "star",
                                           description: Text("Star a team or league in the Sports window."))
                }
                if !leagues.isEmpty {
                    Section("Leagues") {
                        ForEach(leagues) { followed in
                            let id = "league/\(followed.leagueID)"
                            if let league = League.with(id: followed.leagueID) {
                                row(id: id, title: league.name, detail: nil) {
                                    LeagueLogo(league: league, size: 20)
                                } star: {
                                    FollowLeagueButton(league: league)
                                }
                                if expanded.contains(id) {
                                    EventToggles(rules: rules, scope: .league(league.id), leagueID: league.id)
                                    Button("Use Default Alerts") { try? context.resetPreferences(at: .league(league.id)) }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                }
                if !teams.isEmpty {
                    Section("Teams") {
                        ForEach(teams) { followed in
                            let ref = Follows.TeamRef(leagueID: followed.leagueID, teamID: followed.teamID)
                            let id = "team/\(ref.leagueID)/\(ref.teamID)"
                            row(id: id, title: followed.displayName, detail: followed.isMuted ? "Muted" : nil) {
                                TeamLogo(team: followed.team, size: 20)
                            } star: {
                                FollowTeamButton(team: followed.team, leagueID: followed.leagueID)
                            }
                            if expanded.contains(id) {
                                Toggle("Mute", isOn: Binding(
                                    get: { followed.isMuted },
                                    set: { followed.isMuted = $0; try? context.save() }
                                ))
                                if !followed.isMuted {
                                    EventToggles(rules: rules, scope: .team(ref), leagueID: followed.leagueID)
                                    Button("Use League Alerts") { try? context.resetPreferences(at: .team(ref)) }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Chevron, logo and name open or close the row; the star beside them unfollows.
    private func row<Logo: View, Star: View>(id: String, title: String, detail: String?,
                                             @ViewBuilder logo: () -> Logo, @ViewBuilder star: () -> Star) -> some View {
        let isOpen = expanded.contains(id)
        return HStack {
            Button {
                withAnimation(.snappy) {
                    if isOpen { expanded.remove(id) } else { expanded.insert(id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    logo()
                    Text(title)
                    if let detail {
                        Text(detail).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows alert settings")
            star()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.yellow)
        }
    }
}

/// Which model writes game summaries, and the Anthropic API key for Claude (kept in the Keychain).
struct ClaudeSettings: View {
    @State private var draft = ""
    @State private var failed = false
    @AppStorage(RecapEngine.storageKey) private var engine = RecapEngine.onDevice
    @AppStorage(RecapEngine.richAlertsKey) private var richAlerts = false
    private var key: ClaudeKey { .shared }

    var body: some View {
        Form {
            Section {
                Picker("Write summaries with", selection: $engine) {
                    ForEach(RecapEngine.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                if let reason = engine.unavailableReason {
                    Text(reason).foregroundStyle(.orange)
                } else {
                    Text(engine == .onDevice
                         ? "Apple’s model runs on this Mac: free, private and works offline."
                         : "Claude writes richer recaps. Usage is billed to your Anthropic account.")
                }
            }
            Section {
                Toggle("Describe scoring plays in alerts", isOn: $richAlerts)
                    .disabled(RecapEngine.onDevice.unavailableReason != nil)
            } footer: {
                Text("Score alerts get a one-line description of the play, like “Daniels finds White for a 9-yard touchdown.” Written by the on-device model, so it never uses Claude tokens. Alerts can arrive up to half a minute later while ESPN posts the play.")
            }
            Section {
                if key.value != nil {
                    LabeledContent("API key", value: "Saved in Keychain")
                    Button("Remove Key", role: .destructive) { key.set("") }
                } else {
                    SecureField("API key", text: $draft, prompt: Text("sk-ant-…"))
                    Button("Save Key") { failed = !key.set(draft); draft = "" }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Anthropic API")
            } footer: {
                if failed {
                    Text("The Keychain couldn’t save the key.").foregroundStyle(.red)
                } else {
                    Text("Only needed for Claude, which uses \(ClaudeService.model). Get a key at console.anthropic.com.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
