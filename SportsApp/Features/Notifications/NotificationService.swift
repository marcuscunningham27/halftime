import OSLog
import SportsKit
import SwiftData
import UserNotifications

nonisolated private let log = Logger(subsystem: "com.marcuscunningham.SportsApp", category: "notifications")

/// Turns scoreboard changes into local notifications: detect, check preferences, de-duplicate, deliver.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum QuietHoursKey {
        static let enabled = "quietHoursEnabled"
        static let start = "quietHoursStart"
        static let end = "quietHoursEnd"
        static let defaultStart = 22 * 60
        static let defaultEnd = 7 * 60
    }

    private let context: ModelContext
    private let provider: any SportsProvider
    private var detector = GameEventDetector()

    init(container: ModelContainer, provider: any SportsProvider) {
        context = container.mainContext
        self.provider = provider
        super.init()
        UNUserNotificationCenter.current().delegate = self
        try? context.pruneNotificationLog(olderThan: .now.addingTimeInterval(-7 * 24 * 3600))
        // Covers follows made before notifications existed; a no-op once the user has answered.
        if (try? context.fetchCount(FetchDescriptor<FollowedTeam>())) ?? 0 > 0
            || (try? context.fetchCount(FetchDescriptor<FollowedLeague>())) ?? 0 > 0 {
            Self.requestAuthorization()
        }
    }

    /// Asks once; macOS remembers the answer and later calls return it without prompting.
    static func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                log.notice("Notification permission granted: \(granted)")
            } catch {
                log.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func process(old: [Game], new: [Game]) {
        let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        let rules = NotificationRules(leagues: (try? context.fetch(FetchDescriptor<FollowedLeague>())) ?? [],
                                      teams: (try? context.fetch(FetchDescriptor<FollowedTeam>())) ?? [],
                                      preferences: (try? context.fetch(FetchDescriptor<NotificationPreference>())) ?? [])
        for game in new {
            for event in detector.events(old: previous[game.id], new: game) where rules.shouldNotify(event.type, for: game) {
                // Logged before sending: a failed save skips the alert rather than risking repeats every poll.
                guard (try? context.markSent(event, gameID: game.id)) == true else { continue }
                if [.scoreUpdate, .leadChange].contains(event.type), UserDefaults.standard.bool(forKey: RecapEngine.richAlertsKey),
                   RecapEngine.onDevice.unavailableReason == nil {
                    Task { deliver(event, for: game, playLine: await playLine(for: game)) }
                } else {
                    deliver(event, for: game)
                }
            }
        }
    }

    /// The on-device line describing the play behind the new score (free, so alerts never spend Claude tokens),
    /// or nil if it can't be had within about 25 seconds (the alert then goes out as usual rather than arriving later).
    private func playLine(for game: Game) async -> String? {
        let provider = provider
        let work = Task { @MainActor () -> String? in
            // ESPN's play-by-play trails the scoreboard by a few seconds, so look again until the scoring play shows up.
            var play: Play?
            for attempt in 0..<5 where play == nil && !Task.isCancelled {
                if attempt > 0 { try? await Task.sleep(for: .seconds(4)) }
                if let detail = try? await provider.gameDetail(for: game) {
                    play = GamePrompt.latestScoringPlay(in: detail, matching: game)
                }
            }
            guard let play, !Task.isCancelled else { return nil }
            let line = try? await RecapEngine.onDevice.playLine(game: game, play: play)
            return Task.isCancelled ? nil : line
        }
        // shortcut: relies on the network and model honouring cancellation; a model that ignores it delays the alert.
        let timeout = Task {
            try await Task.sleep(for: .seconds(25))
            work.cancel()
        }
        let line = await work.value
        timeout.cancel()
        return line
    }

    private func deliver(_ event: GameEvent, for game: Game, playLine: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "\(game.away.team.shortName) at \(game.home.team.shortName)"
        content.subtitle = event.headline
        content.body = [playLine, event.body].compactMap { $0 }.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = game.id

        let defaults = UserDefaults.standard
        let quietHours = QuietHours(isEnabled: defaults.bool(forKey: QuietHoursKey.enabled),
                                    start: defaults.object(forKey: QuietHoursKey.start) as? Int ?? QuietHoursKey.defaultStart,
                                    end: defaults.object(forKey: QuietHoursKey.end) as? Int ?? QuietHoursKey.defaultEnd)
        var identifier = "\(game.id)-\(event.key)"
        var trigger: UNNotificationTrigger?
        if let release = quietHours.holdUntil(.now) {
            // One held alert per game, replaced by newer ones, so the morning brings the latest state rather than a pile.
            identifier = "\(game.id)-held"
            trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: release), repeats: false)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { [identifier] error in
            if let error { log.error("Couldn’t deliver \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Show banners even while Sports is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
