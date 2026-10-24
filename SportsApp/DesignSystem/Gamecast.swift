import SportsKit
import SwiftUI

/// ESPN Gamecast around a playing surface: the last play in a banner over it, timeouts (and basketball's
/// fouls) for each side under it, then the three latest plays.
struct GamecastView<Surface: View>: View {
    let game: Game
    let plays: [Play]
    let court: CourtSituation?
    @ViewBuilder let surface: Surface

    /// Plays worth listing: substitutions, stoppages and period or game ends are noise here,
    /// and baseball lists at-bat results rather than every pitch.
    private var recent: [Play] {
        plays.filter { play in
            if game.leagueID == League.mlb.id { return play.type == "Play Result" }
            return play.teamID != nil && !play.text.isEmpty && !Self.skipped.contains(play.type ?? "")
                && play.type != "Stoppage" && !isMarker(play)
        }
        .suffix(3).reversed()
    }

    /// The banner's play: the very latest, including timeouts and period or game ends.
    private var latest: Play? {
        plays.last { !$0.text.isEmpty && !Self.skipped.contains($0.type ?? "") }
    }

    /// Never banner- or list-worthy: line-up changes and soccer's injury delays.
    private static var skipped: Set<String> { ["Substitution", "Start Delay", "End Delay"] }

    var body: some View {
        VStack(spacing: 12) {
            if let last = latest {
                LastPlayBanner(game: game, play: last)
                    .id(last.id)
                    .transition(.push(from: .top))
            }
            surface
            if let court, court.powerPlay || court.emptyNet {
                HStack(spacing: 8) {
                    if court.powerPlay {
                        let team = CourtSituation.powerPlayTeam(after: plays, awayID: game.away.team.id, homeID: game.home.team.id)
                            .flatMap { id in [game.away.team, game.home.team].first { $0.id == id } }
                        Pill(text: ["Power Play", team?.abbreviation].compactMap { $0 }.joined(separator: " · "), color: team?.color ?? .orange)
                    }
                    if court.emptyNet { Pill(text: "Empty Net", color: .red) }
                }
            }
            if let court, [court.away, court.home].contains(where: { $0.timeoutsLeft != nil || $0.fouls != nil }) {
                HStack(alignment: .top) {
                    TeamCourtStatus(team: game.away.team, side: court.away, timeouts: timeoutsPerGame, alignment: .leading)
                    Spacer()
                    TeamCourtStatus(team: game.home.team, side: court.home, timeouts: timeoutsPerGame, alignment: .trailing)
                }
            }
            if !recent.isEmpty {
                VStack(spacing: 0) {
                    ForEach(recent) { play in
                        RecentPlayRow(game: game, play: play)
                        if play.id != recent.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
            }
        }
        .animation(.snappy, value: latest?.id)
    }

    /// NFL teams get three timeouts a half, NBA teams seven a game, WNBA teams five.
    private var timeoutsPerGame: Int {
        switch game.leagueID {
        case League.nfl.id, League.cfb.id: 3
        case League.wnba.id: 5
        default: 7
        }
    }
}

/// The play's team. Football files timeouts under the drive's team, so read "Timeout #1 by SF" instead.
private func playTeam(_ play: Play, in game: Game) -> Team? {
    let teams = [game.away.team, game.home.team]
    if play.type?.lowercased().contains("timeout") == true, let range = play.text.range(of: " by ") {
        let caller = play.text[range.upperBound...].prefix { $0.isLetter }
        if let team = teams.first(where: { $0.abbreviation == caller }) { return team }
    }
    return teams.first { $0.id == play.teamID }
}

/// Marks one of your fantasy players: a yellow star, with the row tinted by `fantasyHighlight`.
struct FantasyBadge: View {
    var body: some View {
        Image(systemName: "star.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, .yellow)
            .accessibilityLabel("Your fantasy player")
    }
}

extension View {
    func fantasyHighlight(_ on: Bool) -> some View {
        background(on ? Color.yellow.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
    }
}

extension Game {
    /// Your fantasy players a play names; fantasy is NFL only, so other sports never match.
    func fantasyPlayers(in play: Play) -> [FantasyPlayer] {
        leagueID == League.nfl.id ? FantasyStore.shared.roster.players(in: play.text) : []
    }
}

/// Period, inning and game ends ("End Period", "End of Game", "Period End", "Start Inning").
private func isMarker(_ play: Play) -> Bool {
    let type = play.type?.lowercased() ?? ""
    return type.hasPrefix("end") || type.hasPrefix("period") || type == "start inning"
}

/// A bold capsule for hockey's power play and empty net.
private struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.mix(with: .white, by: 0.1), in: .capsule)
    }
}

/// The latest play as a headline over the court, e.g. "+3 POINTS" beside the team's logo,
/// sliding in from above whenever a new play arrives.
private struct LastPlayBanner: View {
    let game: Game
    let play: Play

    /// ESPN's headline ("+3 Points", "Timeout", "End of 1st"), with a finished game always reading "End of Game".
    private var title: String {
        if game.status == .final { return "End of Game" }
        if play.type?.lowercased().contains("timeout") == true { return "Timeout" }
        // ESPN's text reads best for breaks ("End of OT", "Middle of the 1st inning").
        if isMarker(play) { return play.headline ?? (play.text.isEmpty ? play.type : play.text) ?? "End of Period" }
        if play.type == "Start Batter/Pitcher" { return "At Bat" }
        return play.headline ?? play.type ?? "Last Play"
    }

    var body: some View {
        // Period ends belong to neither team (football files them under the last drive's).
        let team = isMarker(play) || game.status == .final ? nil : playTeam(play, in: game)
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                if let team { TeamLogo(team: team, size: 30) }
                if !game.fantasyPlayers(in: play).isEmpty { FantasyBadge().font(.title2) }
                Text(title.uppercased())
                    .font(.score(34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            // A period end's text only repeats the title.
            if !isMarker(play) {
                Text(play.text)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background((team?.color ?? .gray).opacity(0.25), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last play: \(play.text)")
    }
}

/// Timeouts left as pips, team fouls this period and a bonus tag.
private struct TeamCourtStatus: View {
    let team: Team
    let side: CourtSituation.Side
    let timeouts: Int
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            if let left = side.timeoutsLeft {
                HStack(spacing: 4) {
                    Text("TOL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(0..<timeouts, id: \.self) { index in
                        Capsule().fill(index < left ? team.color.mix(with: .white, by: 0.25) : .white.opacity(0.15))
                            .frame(width: 10, height: 4)
                    }
                }
            }
            HStack(spacing: 6) {
                if let fouls = side.fouls {
                    Text("Fouls \(fouls)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if side.inBonus {
                    Text("BONUS").font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.orange.opacity(0.8), in: .capsule)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.shortName): \(side.timeoutsLeft.map { "\($0) timeouts left" } ?? ""), "
            + "\(side.fouls.map { "\($0) team fouls" } ?? "")\(side.inBonus ? ", in the bonus" : "")")
    }
}

/// One play: logo, headline, clock and text, with the score after it (the scoring side in bold).
private struct RecentPlayRow: View {
    let game: Game
    let play: Play

    var body: some View {
        let team = playTeam(play, in: game)
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let team { TeamLogo(team: team, size: 20) } else { Color.clear }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(play.headline ?? play.type ?? "").font(.subheadline.weight(.semibold))
                    ForEach(game.fantasyPlayers(in: play), id: \.id) { player in
                        FantasyBadge()
                        Text(player.name).font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    }
                }
                Text([play.clock, game.league.periodTitle(play.period), play.spot ?? ""].filter { !$0.isEmpty }.joined(separator: " - "))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(play.text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let away = play.awayScore, let home = play.homeScore {
                let scorer = play.isScoring ? play.teamID : nil
                HStack(spacing: 8) {
                    Text("\(away)").fontWeight(scorer == game.away.team.id ? .bold : .regular)
                        .foregroundStyle(scorer == game.away.team.id ? .primary : .secondary)
                    Text("\(home)").fontWeight(scorer == game.home.team.id ? .bold : .regular)
                        .foregroundStyle(scorer == game.home.team.id ? .primary : .secondary)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .fantasyHighlight(!game.fantasyPlayers(in: play).isEmpty)
        .padding(.horizontal, -6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// The attacking side shaded in the team's colour, with chevrons running toward the basket or end zone.
struct PossessionOverlay: View {
    let color: Color
    let towardLeft: Bool
    /// Where the shading and chevrons start, as a share of the width: centre court, or football's line of scrimmage.
    var from: CGFloat = 0.5

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let start = size.width * from, end: CGFloat = towardLeft ? 0 : size.width
                let span = abs(end - start), dir: CGFloat = towardLeft ? -1 : 1, h = size.height
                context.fill(Path(CGRect(x: min(start, end), y: 0, width: span, height: h)), with: .linearGradient(
                    Gradient(colors: [color.opacity(0.55), color.opacity(0.05)]),
                    startPoint: CGPoint(x: end, y: h / 2), endPoint: CGPoint(x: start, y: h / 2)))
                // Three chevrons drifting from the start toward the end, fading as they go; sized to the surface's
                // height (on the 94 × 50 ft court: 3 ft wide, 14 ft tall, from 6 to 28 ft past half court).
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                for index in 0..<3 {
                    let t = (Double(index) / 3 + phase).truncatingRemainder(dividingBy: 1)
                    let x = start + dir * span * (6 + t * 22) / 47
                    var chevron = Path()
                    chevron.move(to: CGPoint(x: x - dir * h * 0.06, y: h * 0.36))
                    chevron.addLine(to: CGPoint(x: x + dir * h * 0.06, y: h * 0.5))
                    chevron.addLine(to: CGPoint(x: x - dir * h * 0.06, y: h * 0.64))
                    context.stroke(chevron, with: .color(.white.opacity(0.55 * sin(t * .pi))),
                                   style: StrokeStyle(lineWidth: h * 0.044, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A ring that keeps rippling out from the latest shot's spot: team colour for a make, white for a miss
/// (team colour for both on ice).
struct LastShotPulse: View {
    let point: CGPoint
    let color: Color
    let made: Bool
    /// Width of the surface in the units `point` is drawn in (court feet by default).
    var units: CGFloat = 94
    /// On a light surface (ice), use the full team colour for makes and misses alike, so it shows.
    var onLight = false

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let scale = size.width / units
                context.scaleBy(x: scale, y: scale)
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                let radius = (1.2 + t * 3.5) * units / 94
                let ring = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                let ink = onLight ? color : made ? color.mix(with: .white, by: 0.3) : .white
                context.stroke(Path(ellipseIn: ring), with: .color(ink.opacity(1 - t)), lineWidth: (onLight ? 0.8 : 0.5) * units / 94)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
