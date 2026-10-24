import Testing
@testable import SportsKit

@Suite struct YardsGainedTests {
    private func snap(from start: Int, to end: Int?) -> Play {
        Play(id: "1", text: "", period: 1, clock: "", teamID: nil, isScoring: false, awayScore: nil, homeScore: nil,
             startYardLine: start, endYardLine: end)
    }

    @Test func homeOffenceGainsAsTheYardLineRises() {
        // Yard lines count from the home goal, so the home offence moves up the numbers.
        #expect(snap(from: 25, to: 35).yardsGained(homeOffense: true) == 10)
        #expect(snap(from: 25, to: 22).yardsGained(homeOffense: true) == -3)
    }

    @Test func awayOffenceGainsAsTheYardLineFalls() {
        #expect(snap(from: 60, to: 48).yardsGained(homeOffense: false) == 12)
        #expect(snap(from: 60, to: 60).yardsGained(homeOffense: false) == 0)
    }

    @Test func noSpotNoYards() {
        #expect(snap(from: 25, to: nil).yardsGained(homeOffense: true) == nil)
    }
}
