import Foundation
import Testing
@testable import SportsKit

/// Serves fixtures by the `dates` query ("current" when absent) and records what was asked for.
final class StubESPN: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: String] = [:]
    nonisolated(unsafe) static var requested: [String] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubESPN.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let day = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "dates" }?.value ?? "current"
        Self.requested.append(day)
        let fixture = Self.responses[day] ?? "nfl-scoreboard-scheduled"
        let data = try! Data(contentsOf: Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")!)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct RecentResultsTests {
    @Test func usesCurrentSlateWhenItHasFinals() async throws {
        StubESPN.responses = ["current": "nfl-scoreboard-live"]
        StubESPN.requested = []
        let results = try await ESPNProvider(session: StubESPN.session()).recentResults(league: .nfl, before: .now)
        #expect(results.count == 13) // 14 games this week, one still live
        #expect(results.allSatisfy { $0.status == .final })
        #expect(results.map(\.startDate) == results.map(\.startDate).sorted(by: >))
        #expect(StubESPN.requested == ["current"])
    }

    @Test func stepsBackADayAtATimeUntilItFindsFinals() async throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let today = Date(timeIntervalSince1970: 1_792_459_200)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let days = ESPNEndpoints.espnDays(covering: calendar.dateInterval(of: .day, for: twoDaysAgo)!)
        // Current slate and yesterday are all upcoming; two days ago has NBA finals.
        StubESPN.responses = Dictionary(uniqueKeysWithValues: days.map { ($0, "nba-scoreboard") })
        StubESPN.requested = []
        let results = try await ESPNProvider(session: StubESPN.session()).recentResults(league: .nba, before: today)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.status == .final })
        #expect(StubESPN.requested.first == "current")
        // Stops after the first local day that reaches finals (at most two local days here), never asking for a day twice.
        #expect(StubESPN.requested.contains { days.contains($0) })
        #expect(StubESPN.requested.count <= 1 + 4)
        #expect(Set(StubESPN.requested).count == StubESPN.requested.count)
    }

    @Test func givesUpAfterAWeek() async throws {
        StubESPN.responses = [:]
        StubESPN.requested = []
        let results = try await ESPNProvider(session: StubESPN.session()).recentResults(league: .nfl, before: .now)
        #expect(results.isEmpty)
        #expect(StubESPN.requested.count == 1 + 8) // current, then 8 distinct ESPN days covering 7 local days
    }
}

extension RecentResultsTests {
    @Test func picksTheLiveGameWithScoresFromTheScoreboard() async throws {
        let kickoff = Date(timeIntervalSince1970: 1_792_455_300) // 401873008, live in the schedule fixture
        let days = ESPNEndpoints.espnDays(covering: Calendar.current.dateInterval(of: .day, for: kickoff)!)
        StubESPN.responses = ["current": "nfl-schedule"].merging(days.map { ($0, "nfl-scoreboard-live") }) { $1 }
        StubESPN.requested = []
        let game = try await ESPNProvider(session: StubESPN.session())
            .featuredGame(for: .init(leagueID: "nfl", teamID: "25"))
        #expect(game?.id == "401873008")
        #expect(game?.status == .live)
        #expect(game?.home.score == 13)
    }
}

@Test func featuredGamePrefersTodaysResultOverTheNextGame() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 3600
    let lastNight = (now - 4 * hour, Optional("post")), lastWeek = (now - 150 * hour, Optional("post"))
    let tomorrow = (now + 20 * hour, Optional("pre")), later = (now + 70 * hour, Optional("pre"))
    #expect(ESPNProvider.featuredIndex([lastWeek, lastNight, tomorrow, later], now: now) == 1)
    #expect(ESPNProvider.featuredIndex([lastWeek, tomorrow, later], now: now) == 1)
    #expect(ESPNProvider.featuredIndex([lastNight, (now - hour, "in"), tomorrow], now: now) == 1)
    #expect(ESPNProvider.featuredIndex([lastWeek], now: now) == 0)
    #expect(ESPNProvider.featuredIndex([], now: now) == nil)
}
