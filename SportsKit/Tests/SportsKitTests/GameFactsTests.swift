import Foundation
import Testing
@testable import SportsKit

private let okc = Team(id: "25", abbreviation: "OKC", displayName: "Oklahoma City Thunder", shortName: "Thunder",
                       colorHex: nil, alternateColorHex: nil, logoURL: nil)
private let sas = Team(id: "24", abbreviation: "SA", displayName: "San Antonio Spurs", shortName: "Spurs",
                       colorHex: nil, alternateColorHex: nil, logoURL: nil)

private func game(_ status: Game.Status, away: [Int], home: [Int], detail: String = "Final") -> Game {
    Game(id: "1", leagueID: League.nba.id, startDate: .now, status: status, period: away.count, clock: "4:12",
         statusDetail: detail, home: .init(team: sas, score: home.reduce(0, +), periodScores: home),
         away: .init(team: okc, score: away.reduce(0, +), periodScores: away))
}

private func basket(_ id: String, team: Team, away: Int, home: Int, period: Int = 2) -> Play {
    Play(id: id, text: "\(team.shortName) basket", period: period, clock: "5:00", teamID: team.id, isScoring: true,
         awayScore: away, homeScore: home, type: "Jump Shot")
}

private let detail = GameDetail(
    plays: [basket("1", team: okc, away: 2, home: 0), basket("2", team: sas, away: 2, home: 3),
            basket("3", team: sas, away: 2, home: 5), basket("4", team: sas, away: 2, home: 8), basket("5", team: okc, away: 4, home: 8)],
    boxScores: [BoxScore(teamID: "24", category: "pitching", title: "", labels: ["IP", "H", "ER", "K"],
                         rows: [.init(id: "p", name: "Ace", stats: ["6.0", "4", "2", "7"]), .init(id: "r", name: "Relief", stats: ["1.0", "0", "0", "1"])])],
    teamStats: [TeamStat(id: 0, label: "3PT", away: "12-30", home: "9-35")],
    overview: GameOverview(leaders: [
        .init(teamID: "25", category: "Points", athlete: "Shai Gilgeous-Alexander", line: "32"),
        .init(teamID: "24", category: "Points", athlete: "Stephon Castle", line: "24"),
        .init(teamID: "25", category: "Rebounds", athlete: "Chet Holmgren", line: "11"),
    ]))

@Test func finalSummaryStatesResultLeadersAndDecidingPeriod() {
    let text = GameFacts.summary(game: game(.final, away: [34, 31, 28, 23], home: [28, 16, 36, 24]), detail: detail)
    #expect(text.hasPrefix("Thunder beat Spurs 116–104."))
    #expect(text.contains("Shai Gilgeous-Alexander (Thunder) 32 points; Stephon Castle (Spurs) 24 points."))
    #expect(text.contains("Thunder did the most damage in Quarter 2, winning it 31–16."))
}

@Test func liveSummaryShowsTheLeadAndLatestScore() {
    let text = GameFacts.summary(game: game(.live, away: [20, 10], home: [18, 8], detail: "4:12 - 2nd"), detail: detail)
    #expect(text.hasPrefix("Thunder lead Spurs 30–26 (4:12 - 2nd)."))
    #expect(text.contains("Latest score: Thunder basket (Quarter 2, 5:00)."))
}

@Test func quickAnswersComeFromTheStats() {
    let g = game(.final, away: [60, 56], home: [50, 54])
    func ask(_ kind: QuickQuestion.Kind) -> String? { GameFacts.answer(.init("q", kind), game: g, detail: detail) }
    #expect(ask(.leaders(["points"])) == "Points: Shai Gilgeous-Alexander (Thunder) 32, Stephon Castle (Spurs) 24.")
    #expect(GameFacts.leadingNumber("264 YDS") == 264 && GameFacts.leadingNumber("21/29, 264 YDS") == 21)
    #expect(ask(.teamStats(["3PT", "Missing"])) == "3PT: Thunder 12-30, Spurs 9-35.")
    #expect(ask(.biggestRun) == "Spurs went on a 8–0 run in Quarter 2.")
    #expect(ask(.boxRows(anchor: "IP", columns: ["IP", "ER", "K"], firstOnly: true)) == "Ace (Spurs): IP 6.0, ER 2, K 7")
    #expect(ask(.model) == nil)
    #expect(ask(.leaders(["assists"])) == nil)
    #expect(QuickQuestion.list(for: League.nba.id).count == 4)
}

@Test func summaryParsesESPNsRecapArticle() throws {
    let json = #"{"plays":[],"article":{"headline":"Thunder roll past Spurs","story":"<p>SAN ANTONIO -- — Shai had 32 &amp; won.</p><p></p><p>Wemby went 1 for 13.</p>","links":{"web":{"href":"https://www.espn.com/nba/recap"}}}}"#
    let recap = try ESPNProvider.parseSummary(Data(json.utf8), leagueID: League.nba.id).overview.recap
    #expect(recap?.headline == "Thunder roll past Spurs")
    #expect(recap?.paragraphs == ["SAN ANTONIO — Shai had 32 & won.", "Wemby went 1 for 13."])
    #expect(recap?.url?.absoluteString == "https://www.espn.com/nba/recap")
}

@Test func typedQuestionsNamingALeaderCategoryUseTheStats() {
    let g = game(.final, away: [60, 56], home: [50, 54])
    #expect(GameFacts.answer(typed: "Who had the most points?", game: g, detail: detail)
            == "Points: Shai Gilgeous-Alexander (Thunder) 32, Stephon Castle (Spurs) 24.")
    #expect(GameFacts.answer(typed: "top rebounders", game: g, detail: detail) == "Rebounds: Chet Holmgren (Thunder) 11.")
    #expect(GameFacts.answer(typed: "Why did the Spurs lose?", game: g, detail: detail) == nil)
}

@Test func typedQuestionsAboutAPlayerReadTheBoxScore() {
    let g = game(.final, away: [60, 56], home: [50, 54])
    let nba = BoxScore(teamID: "24", category: "players-0", title: "Spurs", labels: ["MIN", "PTS", "REB", "AST"],
                       rows: [.init(id: "1", name: "Devin Booker", stats: ["34", "23", "4", "6"]),
                              .init(id: "2", name: "Jaren Jackson Jr.", stats: ["30", "18", "9", "1"])])
    let box = GameDetail(plays: [], boxScores: [nba], teamStats: [], overview: detail.overview)
    #expect(GameFacts.answer(typed: "how many rebounds does booker have?", game: g, detail: box) == "Devin Booker (Spurs): 4 REB.")
    #expect(GameFacts.answer(typed: "Booker points and assists", game: g, detail: box) == "Devin Booker (Spurs): 23 PTS, 6 AST.")
    #expect(GameFacts.answer(typed: "How did Jackson play?", game: g, detail: box) == "Jaren Jackson Jr. (Spurs): 30 MIN, 18 PTS, 9 REB, 1 AST.")
    // No player named: the leaders still answer.
    #expect(GameFacts.answer(typed: "most points?", game: g, detail: box)?.hasPrefix("Points:") == true)
}
