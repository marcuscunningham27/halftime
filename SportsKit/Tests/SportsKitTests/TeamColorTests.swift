import Testing
@testable import SportsKit

@Suite struct TeamColorTests {
    private func team(_ color: String?, _ alternate: String?) -> Team {
        Team(id: "1", abbreviation: "T", displayName: "T", shortName: "T", colorHex: color, alternateColorHex: alternate, logoURL: nil)
    }

    @Test func colourlessTeamsUseTheirAlternate() {
        #expect(team("ffffff", "0B1426").backdropHex == "0B1426") // Spurs: white, navy alternate
        #expect(team("c0c0c0", "002244").backdropHex == "002244") // silver
    }

    @Test func colouredTeamsKeepTheirOwn() {
        #expect(team("87cced", "ffffff").backdropHex == "87cced") // Coventry's sky blue
        #expect(team("ffffff", nil).backdropHex == "ffffff")     // nothing better to use
        #expect(team("ffffff", "f5f5f5").backdropHex == "ffffff") // alternate's no better
    }
}
