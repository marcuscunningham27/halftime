import Testing
@testable import SportsKit

@Suite struct ContrastTests {
    @Test func darkColoursAreLeftAlone() {
        #expect(Contrast.readableScale(45 / 255, 101 / 255, 38 / 255) == 1) // Home green
        #expect(Contrast.readableScale(0.07, 0.13, 0.34) == 1)             // Spurs navy
    }

    @Test(arguments: [(1.0, 1.0, 1.0), (0.65, 0.85, 1.0), (1.0, 0.85, 0.1), (0.9, 0.9, 0.9)])
    func paleColoursAreDarkenedUntilWhiteTextReads(_ c: (Double, Double, Double)) {
        let boost = 1.225 // a backdrop's lightest fold
        let scale = Contrast.readableScale(c.0, c.1, c.2, boost: boost)
        #expect(scale < 1)
        let k = min(scale * boost, 1 / max(c.0, c.1, c.2))
        #expect(Contrast.whiteRatio(c.0 * k, c.1 * k, c.2 * k) >= Contrast.minimumRatio)
        // Darkened only as far as needed, not to black.
        #expect(Contrast.whiteRatio(c.0 * k * 1.05, c.1 * k * 1.05, c.2 * k * 1.05) < Contrast.minimumRatio + 0.6)
    }
}
