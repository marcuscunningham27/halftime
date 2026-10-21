import Foundation
import Testing
@testable import SportsKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct ClaudeTests {
    @Test func parsesTextBlocks() throws {
        let json = #"{"content":[{"type":"text","text":"  The Chiefs won. "},{"type":"text","text":"Easily."}]}"#
        #expect(try ClaudeService.parse(Data(json.utf8)) == "The Chiefs won. Easily.")
    }

    @Test func emptyAnswerThrows() {
        #expect(throws: ClaudeService.ClaudeError.self) { try ClaudeService.parse(Data(#"{"content":[]}"#.utf8)) }
    }

    @Test func readsAPIErrorMessage() {
        let json = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        #expect(ClaudeService.errorMessage(Data(json.utf8)) == "invalid x-api-key")
    }

    @Test func recapPromptIsGroundedInGameData() throws {
        let game = try #require(try ESPNProvider.parseScoreboard(fixture("nfl-scoreboard-live"), leagueID: League.nfl.id).first)
        let detail = try ESPNProvider.parseSummary(fixture("nfl-summary-final"))
        let prompt = GamePrompt.recap(game: game, detail: detail)
        #expect(prompt.contains("Score: \(game.away.team.shortName) \(game.away.score ?? 0), \(game.home.team.shortName) \(game.home.score ?? 0)"))
        let scoringLines = prompt.components(separatedBy: "\n").drop { $0 != "Scoring plays:" }.dropFirst().prefix { $0.hasPrefix("- ") }
        #expect(scoringLines.count == detail.plays.filter(\.isScoring).count)
        #expect(prompt.contains("Team stats"))
        if game.away.periodScores.count > 0 {
            let a = game.away.periodScores[0], h = game.home.periodScores[0]
            #expect(prompt.contains("After period 1: \(game.away.team.shortName) \(a), \(game.home.team.shortName) \(h)"))
        }
    }

    @Test func liveGamesGetCatchUpWithSituation() throws {
        let game = try #require(ESPNProvider.parseScoreboard(fixture("nfl-scoreboard-live"), leagueID: League.nfl.id).first { $0.status == .live })
        let detail = try ESPNProvider.parseSummary(fixture("nfl-summary-live"))
        #expect(GamePrompt.system(for: game).contains("Watch for"))
        #expect(GamePrompt.recap(game: game, detail: detail).contains("Now: period \(game.period), \(game.clock) left"))
    }

    @Test func scoringPlayMustMatchTheBoard() throws {
        let detail = try ESPNProvider.parseSummary(fixture("nfl-summary-final"))
        let game = try #require(try ESPNProvider.parseScoreboard(fixture("nfl-scoreboard-live"), leagueID: League.nfl.id).first)
        let last = try #require(detail.plays.last { $0.isScoring })
        // The fixture game's score differs from the summary's last scoring play, so it's stale and skipped.
        if game.away.score != last.awayScore || game.home.score != last.homeScore {
            #expect(GamePrompt.latestScoringPlay(in: detail, matching: game) == nil)
        }
        #expect(GamePrompt.playLine(game: game, play: last).contains(last.text))
    }

    @Test func askPromptCarriesBoxScoreAndQuestion() throws {
        let game = try #require(try ESPNProvider.parseScoreboard(fixture("nfl-scoreboard-live"), leagueID: League.nfl.id).first)
        let detail = try ESPNProvider.parseSummary(fixture("nfl-summary-final"))
        let prompt = GamePrompt.ask("Who threw for the most yards?", game: game, detail: detail)
        #expect(prompt.hasSuffix("Question: Who threw for the most yards?"))
        #expect(prompt.contains("- Justin Herbert: 22/37"))
        // The on-device model has a ~4k-token window; ~4 characters a token leaves room for the answer.
        #expect(prompt.count < 12_000, "prompt is \(prompt.count) characters")
    }

    @Test func thinkingOnlyReplyIsCutOffNotEmpty() throws {
        let thinkingOnly = #"{"content":[{"type":"thinking","thinking":""}],"stop_reason":"max_tokens"}"#
        #expect(throws: ClaudeService.ClaudeError.self) { try ClaudeService.parse(Data(thinkingOnly.utf8)) }
        let mixed = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Recap."}],"stop_reason":"end_turn"}"#
        #expect(try ClaudeService.parse(Data(mixed.utf8)) == "Recap.")
        do {
            _ = try ClaudeService.parse(Data(thinkingOnly.utf8))
        } catch ClaudeService.ClaudeError.cutOff {
        } catch {
            Issue.record("expected cutOff, got \(error)")
        }
    }

    @Test func scoringPlayFoundByScoreEvenWhenNewerPlaysExist() throws {
        let game = try #require(try ESPNProvider.parseScoreboard(fixture("nfl-scoreboard-live"), leagueID: League.nfl.id).first)
        let a = game.away.score ?? 0, h = game.home.score ?? 0
        func play(_ id: String, _ away: Int, _ home: Int, scoring: Bool = true) -> Play {
            Play(id: id, text: id, period: 2, clock: "5:00", teamID: nil, isScoring: scoring, awayScore: away, homeScore: home)
        }
        let detail = GameDetail(plays: [play("before", a - 3, h), play("it", a, h), play("miss", a, h, scoring: false), play("after", a, h + 2)],
                                boxScores: [], teamStats: [])
        #expect(GamePrompt.latestScoringPlay(in: detail, matching: game)?.id == "it")
    }
}
