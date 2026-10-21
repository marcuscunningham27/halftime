/// Live state ESPN's scoreboard doesn't carry: timeouts, plus team fouls and bonus in basketball.
public struct CourtSituation: Hashable, Sendable {
    public struct Side: Hashable, Sendable {
        public let timeoutsLeft: Int?
        /// Team fouls this period.
        public let fouls: Int?
        public let inBonus: Bool

        public init(timeoutsLeft: Int?, fouls: Int?, inBonus: Bool) {
            self.timeoutsLeft = timeoutsLeft
            self.fouls = fouls
            self.inBonus = inBonus
        }
    }

    public let away: Side
    public let home: Side
    /// Hockey: a team is on the power play, or has pulled its goalie.
    public let powerPlay: Bool
    public let emptyNet: Bool

    public init(away: Side, home: Side, powerPlay: Bool = false, emptyNet: Bool = false) {
        self.away = away
        self.home = home
        self.powerPlay = powerPlay
        self.emptyNet = emptyNet
    }

    /// Hockey: the team on the power play is the one the latest penalty was against
    /// ("Jakub Dobes Interference against Collin Graf"), which ESPN files under the offender's team.
    public static func powerPlayTeam(after plays: [Play], awayID: Team.ID, homeID: Team.ID) -> Team.ID? {
        guard let penalty = plays.last(where: { $0.text.contains(" against ") }) else { return nil }
        return penalty.teamID == awayID ? homeID : penalty.teamID == homeID ? awayID : nil
    }

    /// Who has the ball after the latest plays, worked out from what happened (ESPN doesn't say):
    /// a rebound gives it to the rebounder, a make, turnover or foul to the other team, a miss stays with the shooter
    /// until the rebound. Timeouts and substitutions are skipped; nil at a period break or when it can't be told.
    public static func possession(after plays: [Play], awayID: Team.ID, homeID: Team.ID) -> Team.ID? {
        func other(_ id: Team.ID?) -> Team.ID? { id == awayID ? homeID : id == homeID ? awayID : nil }
        for play in plays.reversed() {
            let type = (play.type ?? "").lowercased()
            if type.contains("end period") || type.contains("end game") { return nil }
            guard let team = play.teamID else { continue }
            if type.contains("rebound") { return team }
            if type.contains("turnover") || type.contains("traveling") { return other(team) }
            if type.contains("technical") { continue } // technical free throws don't change possession
            if type.hasPrefix("free throw") {
                // Only the last free throw of a trip hands the ball over, and only when it goes in.
                let words = type.split(separator: " ")
                let last = words.count >= 3 && words[words.count - 3] == words[words.count - 1]
                return play.isScoring && last ? other(team) : team
            }
            if play.isShot { return play.isScoring ? other(team) : team }
            // Fouls are listed under the fouling team, so the other team has it (offensive fouls are turnovers above).
            if type.contains("foul") && !type.contains("loose ball") { return other(team) }
        }
        return nil
    }
}
