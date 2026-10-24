import Foundation
import Testing
@testable import SportsKit

@Suite struct BaseballResultTests {
    @Test(arguments: [
        ("Kwan reached on infield single to shortstop.", "Single"),
        ("Ramírez flied out to left.", "Fly Out"),
        ("Hicks grounded out to second, Mateo scored.", "Ground Out"),
        ("DeLuca struck out swinging.", "Strikeout"),
        ("Caminero walked.", "Walk"),
        ("Lowe hit by pitch.", "Hit By Pitch"),
        ("Naylor grounded into double play, second to shortstop to first.", "Double Play"),
        ("Aranda hit sacrifice fly to center, Lowe scored.", "Sacrifice Fly"),
        ("Caminero homered to left (402 feet).", "Home Run"),
        ("Bauers reached on throwing error by shortstop.", "Error"),
        ("Festa relieved Armstrong.", "Pitching Change"),
        ("Kwan stole second.", "Stolen Base"),
        ("Bell ran for Naylor.", "Substitution"),
        ("Something new happened.", nil),
    ] as [(String, String?)])
    func namesResultsFromTheirText(_ text: String, _ name: String?) {
        #expect(Play.baseballResult(text) == name)
    }

    @Test func resultRowsGetNamedInTheSummary() throws {
        let url = try #require(Bundle.module.url(forResource: "mlb-summary", withExtension: "json", subdirectory: "Fixtures"))
        let plays = try ESPNProvider.parseSummary(Data(contentsOf: url), leagueID: League.mlb.id).plays.filter { $0.type == "Play Result" }
        #expect(plays.first { $0.text.hasPrefix("Kwan reached on infield single") }?.headline == "Single")
        #expect(plays.contains { $0.headline == "Strikeout" })
        #expect(plays.contains { $0.headline == "Walk" })
        #expect(plays.contains { $0.headline == "Pitching Change" })
        #expect(plays.first { $0.text.hasPrefix("Kwan reached") }?.isBaseHit == true)
        #expect(plays.first { $0.text.hasPrefix("Ramírez flied out") }?.isBaseHit == false)
    }
}
