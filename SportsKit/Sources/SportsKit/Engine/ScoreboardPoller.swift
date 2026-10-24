import Foundation
import Observation

/// Keeps one day's games fresh for a set of leagues, polling on the SPEC.md schedule:
/// 15 s while a game is live, up to 5 min while games are upcoming, stopped once everything is final,
/// and exponential backoff (capped at 2 min) after errors.
///
/// No explicit sleep/wake handling: the process is suspended while the Mac sleeps, and
/// `Task.sleep` runs on the continuous clock, so an overdue poll fires as soon as it wakes.
@MainActor @Observable
public final class ScoreboardPoller {
    public private(set) var games: [Game] = []
    public private(set) var error: Error?
    public private(set) var isLoading = false

    private let provider: any SportsProvider
    /// Read on every refresh, so changes apply from the next poll.
    public var leagues: [League]
    /// nil follows today and rolls over at midnight.
    private let date: Date?
    /// Called after each successful fetch with the previous and new games, for change detection.
    public var onUpdate: ((_ old: [Game], _ new: [Game]) -> Void)?
    /// True while `games` is last launch's cached copy, so the first real fetch isn't compared against it.
    private var showingCache = false

    public init(provider: any SportsProvider, leagues: [League], date: Date? = nil) {
        self.provider = provider
        self.leagues = leagues
        self.date = date
    }

    /// Polls until the calling task is cancelled (run it from `.task`), or until a fixed day is all final.
    public func run() async {
        await seedFromCache()
        var failures = 0
        while !Task.isCancelled {
            failures = await refresh() ? 0 : failures + 1
            guard let delay = Self.nextPoll(after: games, failures: failures, now: .now) ?? untilTomorrow() else { return }
            try? await Task.sleep(for: delay)
        }
    }

    /// Fills `games` from the provider's disk cache, so screens draw at once instead of waiting on the network.
    public func seedFromCache() async {
        guard games.isEmpty else { return }
        // Counts as loading, so screens show their spinner rather than flash "No games".
        isLoading = true
        defer { isLoading = false }
        let provider = provider, day = date ?? .now
        var cached: [Game] = []
        for league in leagues { cached += await provider.cachedScoreboard(league: league, date: day) }
        guard games.isEmpty, !cached.isEmpty else { return }
        games = cached.sorted { $0.startDate < $1.startDate }
        showingCache = true
    }

    /// Fetches once. Returns false on a network or decoding error.
    @discardableResult
    public func refresh() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let provider = provider, day = date ?? .now
            let results = await withTaskGroup(of: Result<[Game], Error>.self) { group in
                for league in leagues {
                    group.addTask {
                        do { return .success(try await provider.scoreboard(league: league, date: day)) }
                        catch { return .failure(error) }
                    }
                }
                var results: [Result<[Game], Error>] = []
                for await result in group { results.append(result) }
                return results
            }
            // One league failing (an endpoint change, say) shouldn't blank the others; only all failing is an error.
            let failures = results.compactMap { result -> Error? in
                if case .failure(let error) = result { error } else { nil }
            }
            if !results.isEmpty, failures.count == results.count { throw failures[0] }
            let games = results.flatMap { (try? $0.get()) ?? [] }
            // Changes while the app was closed (a game going final) aren't news, so a cached start compares as a first load.
            let old = showingCache ? [] : self.games
            showingCache = false
            self.games = games.sorted { $0.startDate < $1.startDate }
            error = nil
            onUpdate?(old, self.games)
            return true
        } catch is CancellationError {
            return true
        } catch {
            self.error = error
            return false
        }
    }

    /// When following today, idle until just after midnight to pick up the new day.
    private func untilTomorrow() -> Duration? {
        guard date == nil, let tomorrow = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 0, second: 1), matchingPolicy: .nextTime)
        else { return nil }
        return .seconds(tomorrow.timeIntervalSinceNow)
    }

    /// The polling policy, kept pure for tests. nil means nothing will change, so stop.
    nonisolated public static func nextPoll(after games: [Game], failures: Int, now: Date) -> Duration? {
        if failures > 0 {
            return .seconds(min(15 << min(failures - 1, 4), 120))
        }
        if games.contains(where: { $0.status == .live }) {
            return .seconds(15)
        }
        if let kickoff = games.filter({ $0.status == .scheduled }).map(\.startDate).min() {
            // Wake for kickoff rather than up to 5 min late; overdue starts (delays) poll every 15 s.
            return .seconds(max(15, min(300, kickoff.timeIntervalSince(now))))
        }
        return nil
    }
}
