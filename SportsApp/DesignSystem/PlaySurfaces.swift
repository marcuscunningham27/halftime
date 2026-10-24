import SportsKit
import SwiftUI

/// The sport's playing surface under the scores, ESPN Gamecast style: football field, baseball diamond,
/// basketball court, hockey rink or soccer pitch, with the plays ESPN gives locations for.
struct PlaySurfaceView: View {
    let game: Game
    let detail: GameDetail?

    var body: some View {
        switch game.leagueID {
        case League.nfl.id, League.cfb.id:
            if let field = FieldState(game: game, detail: detail) {
                GamecastView(game: game, plays: detail?.plays ?? [], court: detail?.court) {
                    FieldView(game: game, state: field)
                }
                .frame(maxWidth: 600)
            }
        case League.mlb.id:
            if game.status == .live || !hits.isEmpty {
                GamecastView(game: game, plays: detail?.plays ?? [], court: detail?.court) {
                    BaseballDiamondView(game: game, plays: detail?.plays ?? [], teamStats: detail?.teamStats ?? [])
                }
                .frame(maxWidth: 600)
            }
        case League.nba.id, League.wnba.id:
            if game.status == .live || !shots.isEmpty {
                GamecastView(game: game, plays: detail?.plays ?? [], court: detail?.court) {
                    BasketballCourtView(game: game, shots: shots, possession: game.status == .live
                        ? CourtSituation.possession(after: detail?.plays ?? [], awayID: game.away.team.id, homeID: game.home.team.id) : nil)
                }
                .frame(maxWidth: 600)
            }
        case League.nhl.id:
            if game.status == .live || !shots.isEmpty {
                GamecastView(game: game, plays: detail?.plays ?? [], court: detail?.court) {
                    HockeyRinkView(game: game, plays: shots)
                }
                .frame(maxWidth: 600)
            }
        case League.epl.id, League.ucl.id, League.mls.id:
            if game.status == .live || !(detail?.shots.isEmpty ?? true) {
                GamecastView(game: game, plays: detail?.plays ?? [], court: nil) {
                    SoccerPitchView(game: game, shots: detail?.shots ?? [], teamStats: detail?.teamStats ?? [])
                }
                .frame(maxWidth: 600)
            }
        default:
            EmptyView()
        }
    }

    private var hits: [Play] { detail?.plays.filter { $0.location != nil } ?? [] }

    /// Located shots, without free throws (they all come from the same spot).
    private var shots: [Play] {
        (detail?.plays ?? []).filter { play in
            guard play.location != nil, let type = play.type?.lowercased() else { return false }
            if game.leagueID == League.nhl.id { return type.contains("shot") || type.contains("goal") }
            return play.isShot && !type.contains("free throw")
        }
    }
}

/// Team for a play, away or home.
private func team(of play: Play, in game: Game) -> Team? {
    [game.away.team, game.home.team].first { $0.id == play.teamID }
}

/// Legend chip: team logo, abbreviation and a stat.
private struct LegendItem: View {
    let team: Team
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(team.color).frame(width: 9, height: 9)
            TeamLogo(team: team, size: 18)
            Text("\(team.abbreviation) \(text)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Baseball

/// ESPN's Gamecast ballpark, styled like the court and football field: an info row (the count, outs and batter
/// while live; runs, hits and errors once it's over), the outfield wall in the home team's colour with its code in
/// centre field, mown grass with the home logo, runners glowing in the batting team's colour, earlier balls in play
/// as dots (filled for hits, hollow for outs) and the latest arcing out with a pulse where it landed.
/// Drawn in ESPN's 250-unit hit-chart space, with home plate at (125, 204).
struct BaseballDiamondView: View {
    let game: Game
    let plays: [Play]
    var teamStats: [TeamStat] = []

    private static let home = CGPoint(x: 125, y: 204)
    private static let first = CGPoint(x: 152.7, y: 176.3)
    private static let second = CGPoint(x: 125, y: 148.6)
    private static let third = CGPoint(x: 97.3, y: 176.3)
    /// The drawing runs from just beyond the wall (its band peaks at y ≈ 21.5) to behind home plate (y = 218).
    private static let top: CGFloat = 18, height: CGFloat = 200

    var body: some View {
        let state = game.status == .live ? game.situation?.baseball : nil
        VStack(spacing: 10) {
            infoRow(state).padding(.bottom, 4)
            GeometryReader { geometry in
                let scale = geometry.size.width / 250
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        context.translateBy(x: 0, y: -Self.top * scale)
                        context.scaleBy(x: scale, y: scale)
                        drawField(&context)
                    }
                    // The home team's code on the centre-field wall and its logo on the grass, as the court has at centre.
                    Text(game.home.team.abbreviation)
                        .font(.system(size: 7 * scale, weight: .heavy).width(.expanded))
                        .foregroundStyle(.white.opacity(0.9))
                        .position(view(CGPoint(x: 125, y: 26), scale))
                    TeamLogo(team: game.home.team, size: 40 * scale)
                        .opacity(0.8)
                        .position(view(CGPoint(x: 125, y: 88), scale))
                    Canvas { context, _ in
                        context.translateBy(x: 0, y: -Self.top * scale)
                        context.scaleBy(x: scale, y: scale)
                        drawBases(&context, state: state)
                        drawHits(&context)
                    }
                    if let last = atBats.last, let spot = last.spot {
                        LastShotPulse(point: CGPoint(x: point(spot).x, y: point(spot).y - Self.top),
                                      color: battingTeam?.color ?? .white, made: last.play.isBaseHit, units: 250)
                            .id(last.play.id)
                    }
                }
            }
            .aspectRatio(250 / Self.height, contentMode: .fit)
            .frame(maxWidth: 420)
            .rotation3DEffect(.degrees(22), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            if let pitcher = state?.pitcher {
                Text("Pitching: \(pitcher)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(state))
    }

    /// COUNT | OUTS | AT BAT while live; RUNS | HITS | ERRORS (away–home) otherwise.
    @ViewBuilder
    private func infoRow(_ state: Game.Situation.Baseball?) -> some View {
        HStack(spacing: 0) {
            if let state {
                GamecastStat(title: "Count", value: "\(state.balls)–\(state.strikes)")
                Divider().frame(height: 34)
                GamecastStat(title: "Outs", value: String(repeating: "●", count: state.outs) + String(repeating: "○", count: max(0, 3 - state.outs)))
                Divider().frame(height: 34)
                GamecastStat(title: "At Bat", value: state.batter)
            } else {
                GamecastStat(title: "Runs", value: game.away.score.flatMap { away in game.home.score.map { "\(away)–\($0)" } })
                Divider().frame(height: 34)
                GamecastStat(title: "Hits", value: stat("Hits"))
                Divider().frame(height: 34)
                GamecastStat(title: "Errors", value: stat("Errors"))
            }
        }
    }

    private func stat(_ label: String) -> String? {
        teamStats.first { $0.label == label }.map { "\($0.away)–\($0.home)" }
    }

    /// The team at the plate: whoever the latest at-bat belongs to.
    private var battingTeam: Team? {
        atBats.last.flatMap { team(of: $0.play, in: game) }
    }

    /// Hit-chart units to this view's points (the chart is scaled to the width and starts at `top`).
    private func view(_ point: CGPoint, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: (point.y - Self.top) * scale)
    }

    /// One entry per at-bat, newest last: its result row (for the words) and where the ball went, if it was
    /// put in play. ESPN puts the spot on the result row in some games and on the "Ball In Play" pitch in others.
    /// A result still to come (live) is represented by the pitch itself.
    private var atBats: [(play: Play, spot: Play.Location?)] {
        var list: [(play: Play, spot: Play.Location?)] = []
        var inPlay: Play?
        for play in plays {
            if play.text.hasSuffix("In Play") {
                inPlay = play
            } else if play.type == "Play Result" {
                list.append((play, play.location ?? inPlay?.location))
                inPlay = nil
            }
        }
        if let inPlay { list.append((inPlay, inPlay.location)) }
        return list
    }

    private func point(_ location: Play.Location) -> CGPoint {
        CGPoint(x: location.x * 250, y: location.y * 250)
    }

    private func drawField(_ context: inout GraphicsContext) {
        let home = Self.home, dirt = Color(red: 0.76, green: 0.58, blue: 0.38)
        func fan(_ reach: CGFloat, _ depth: CGFloat) -> Path {
            Path { path in
                path.move(to: home)
                path.addLine(to: CGPoint(x: home.x - reach, y: home.y - reach))
                path.addQuadCurve(to: CGPoint(x: home.x + reach, y: home.y - reach), control: CGPoint(x: home.x, y: home.y - depth))
                path.closeSubpath()
            }
        }
        // The outfield wall in the home team's colour, then the warning track inside it.
        var wall = Path()
        wall.move(to: CGPoint(x: home.x - 121, y: home.y - 121))
        wall.addQuadCurve(to: CGPoint(x: home.x + 121, y: home.y - 121), control: CGPoint(x: home.x, y: home.y - 236))
        context.stroke(wall, with: .color(game.home.team.backdropColor), style: StrokeStyle(lineWidth: 8, lineCap: .butt))
        context.fill(fan(118, 230), with: .color(dirt.mix(with: .black, by: 0.15)))
        // Grass mown in stripes, in the football field's turf greens, lit like the court.
        let grass = fan(112, 220)
        context.drawLayer { layer in
            layer.clip(to: grass)
            for band in stride(from: CGFloat(20), to: 220, by: 12) {
                layer.fill(Path(CGRect(x: 0, y: band, width: 250, height: 12)),
                           with: .color(Int(band / 12).isMultiple(of: 2) ? Color.turfLight : Color.turfDark))
            }
            layer.fill(Path(CGRect(x: 0, y: 0, width: 250, height: 250)), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.1), .clear, .black.opacity(0.12)]),
                startPoint: CGPoint(x: 0, y: 30), endPoint: CGPoint(x: 250, y: 220)))
        }
        // Infield dirt and the grass square inside the bases.
        context.fill(fan(50, 98), with: .color(dirt))
        var square = Path()
        square.move(to: CGPoint(x: home.x, y: home.y - 6))
        square.addLine(to: CGPoint(x: Self.first.x - 6, y: Self.first.y))
        square.addLine(to: CGPoint(x: Self.second.x, y: Self.second.y + 6))
        square.addLine(to: CGPoint(x: Self.third.x + 6, y: Self.third.y))
        square.closeSubpath()
        context.fill(square, with: .color(.turfLight))
        // Chalk: foul lines out to the wall and the batter's boxes; the mound with its rubber; the plate's dirt circle.
        let chalk = GraphicsContext.Shading.color(.white.opacity(0.9))
        var lines = Path()
        lines.move(to: CGPoint(x: home.x - 118, y: home.y - 118)); lines.addLine(to: home)
        lines.addLine(to: CGPoint(x: home.x + 118, y: home.y - 118))
        context.stroke(lines, with: chalk, lineWidth: 1)
        context.fill(Path(ellipseIn: CGRect(x: home.x - 10, y: home.y - 7, width: 20, height: 14)), with: .color(dirt))
        for side in [-1.0, 1.0] {
            context.stroke(Path(CGRect(x: home.x + side * 4 - (side < 0 ? 4 : 0), y: home.y - 4, width: 4, height: 8)), with: chalk, lineWidth: 0.6)
        }
        context.fill(Path(ellipseIn: CGRect(x: 119, y: 171, width: 12, height: 12)), with: .color(dirt.mix(with: .white, by: 0.1)))
        context.fill(Path(CGRect(x: 123, y: 176.5, width: 4, height: 1)), with: chalk)
    }

    private func drawBases(_ context: inout GraphicsContext, state: Game.Situation.Baseball?) {
        let occupied = [state?.onFirst ?? false, state?.onSecond ?? false, state?.onThird ?? false]
        let runnerColor = battingTeam?.color ?? Color(red: 0.2, green: 0.45, blue: 1)
        for (index, base) in [Self.first, Self.second, Self.third].enumerated() {
            let diamond = Path { path in
                path.move(to: CGPoint(x: base.x, y: base.y - 5.5)); path.addLine(to: CGPoint(x: base.x + 5.5, y: base.y))
                path.addLine(to: CGPoint(x: base.x, y: base.y + 5.5)); path.addLine(to: CGPoint(x: base.x - 5.5, y: base.y))
                path.closeSubpath()
            }
            if occupied[index] {
                // A runner: the base glows in the batting team's colour.
                context.fill(Path(ellipseIn: CGRect(x: base.x - 10, y: base.y - 10, width: 20, height: 20)), with: .color(runnerColor.opacity(0.35)))
                context.fill(diamond, with: .color(runnerColor))
                context.stroke(diamond, with: .color(.white), lineWidth: 1)
            } else {
                context.fill(diamond, with: .color(.white))
            }
        }
        var plate = Path()
        plate.move(to: CGPoint(x: Self.home.x - 3, y: Self.home.y - 2)); plate.addLine(to: CGPoint(x: Self.home.x + 3, y: Self.home.y - 2))
        plate.addLine(to: CGPoint(x: Self.home.x + 3, y: Self.home.y)); plate.addLine(to: CGPoint(x: Self.home.x, y: Self.home.y + 2.5))
        plate.addLine(to: CGPoint(x: Self.home.x - 3, y: Self.home.y)); plate.closeSubpath()
        context.fill(plate, with: .color(.white))
    }

    private func drawHits(_ context: inout GraphicsContext) {
        let atBats = atBats
        // Earlier balls in play: filled in the team's colour for hits, hollow for outs, as the court marks makes and misses.
        for (play, location) in atBats.dropLast().compactMap({ at in at.spot.map { (at.play, $0) } }).suffix(7) {
            let spot = point(location), color = team(of: play, in: game)?.color ?? .white
            let dot = Path(ellipseIn: CGRect(x: spot.x - 3.5, y: spot.y - 3.5, width: 7, height: 7))
            if play.isBaseHit {
                context.fill(dot, with: .color(color))
                context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 0.8)
            } else {
                // A dark casing under the ring keeps it readable on dirt and grass, whatever the team colour.
                context.stroke(dot, with: .color(.black.opacity(0.55)), lineWidth: 3)
                context.stroke(dot, with: .color(color.mix(with: .white, by: 0.45)), lineWidth: 1.5)
            }
        }
        guard let last = atBats.last, let location = last.spot else { return }
        let spot = point(location)
        let words = "\(last.play.headline ?? last.play.type ?? "") \(last.play.text)".lowercased()
        var path = Path()
        path.move(to: Self.home)
        // Fly balls and homers arc; grounders and liners run flat, as on ESPN.
        if ["flied", "fly", "popped", "pop", "homer", "home run", "sacrifice fly", "foul out", "fouled out"].contains(where: words.contains) {
            path.addQuadCurve(to: spot, control: CGPoint(x: (Self.home.x + spot.x) / 2, y: min(Self.home.y, spot.y) - 70))
        } else {
            path.addLine(to: spot)
        }
        // White casing under the batting team's colour, like the court's last basket.
        let color = battingTeam?.color ?? .white
        context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        context.stroke(path, with: .color(color.mix(with: .white, by: 0.2)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        context.stroke(Path(ellipseIn: CGRect(x: spot.x - 4.5, y: spot.y - 4.5, width: 9, height: 9)), with: .color(.white), lineWidth: 1.2)
    }

    private func accessibilityText(_ state: Game.Situation.Baseball?) -> String {
        var parts: [String] = []
        if let state {
            parts.append("\(state.balls) balls, \(state.strikes) strikes, \(state.outs) outs")
            let bases = [state.onFirst ? "first" : nil, state.onSecond ? "second" : nil, state.onThird ? "third" : nil].compactMap { $0 }
            parts.append(bases.isEmpty ? "bases empty" : "runners on \(bases.joined(separator: ", "))")
        }
        if let last = atBats.last { parts.append(last.play.text) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Basketball

/// Full court shot chart: the away team's shots at the left basket, the home team's at the right;
/// filled for makes, hollow for misses. Drawn in feet (94 × 50).
struct BasketballCourtView: View {
    let game: Game
    let shots: [Play]
    /// Team with the ball; its half is shaded with chevrons running at the basket.
    var possession: Team.ID? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                legend(game.away.team)
                Spacer()
                legend(game.home.team)
            }
            ZStack {
                Canvas { context, size in
                    let scale = size.width / 94
                    context.scaleBy(x: scale, y: scale)
                    drawCourt(&context)
                }
                if let possession, let team = [game.away.team, game.home.team].first(where: { $0.id == possession }) {
                    PossessionOverlay(color: team.color, towardLeft: team.id == game.away.team.id)
                        .id(team.id)
                        .transition(.opacity)
                }
                // The home team's logo at centre court, under the shots.
                GeometryReader { proxy in
                    TeamLogo(team: game.home.team, size: proxy.size.height * 0.34)
                        .opacity(0.85)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                Canvas { context, size in
                    let scale = size.width / 94
                    context.scaleBy(x: scale, y: scale)
                    drawShots(&context)
                    drawLastBasket(&context)
                }
                if let shot = shots.last, let (point, team) = spot(shot) {
                    LastShotPulse(point: point, color: team.color, made: shot.isScoring).id(shot.id)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: possession)
            .aspectRatio(94 / 50, contentMode: .fit)
            .rotation3DEffect(.degrees(20), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            // Hoops stand up out of the floor, so they sit outside the tilt, over each basket.
            .overlay(alignment: .leading) { Hoop(padColor: game.home.team.backdropColor).offset(x: -10, y: -34) }
            .overlay(alignment: .trailing) { Hoop(padColor: game.home.team.backdropColor).scaleEffect(x: -1).offset(x: 10, y: -34) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shot chart. " + [game.away.team, game.home.team].map { "\($0.shortName) \(made($0)) of \(attempts($0))" }.joined(separator: ", "))
    }

    private func attempts(_ team: Team) -> Int { shots.filter { $0.teamID == team.id }.count }
    private func made(_ team: Team) -> Int { shots.filter { $0.teamID == team.id && $0.isScoring }.count }

    private func legend(_ team: Team) -> some View {
        LegendItem(team: team, text: "\(made(team))/\(attempts(team)) FG")
    }

    private func drawCourt(_ context: inout GraphicsContext) {
        let floor = Path(roundedRect: CGRect(x: 0, y: 0, width: 94, height: 50), cornerRadius: 1)
        context.fill(floor, with: .linearGradient(Gradient(colors: [Color(red: 0.80, green: 0.60, blue: 0.38), Color(red: 0.72, green: 0.52, blue: 0.32)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 94, y: 50)))
        let line = GraphicsContext.Shading.color(.white.opacity(0.9))
        context.stroke(floor, with: line, lineWidth: 0.35)
        var center = Path()
        center.move(to: CGPoint(x: 47, y: 0)); center.addLine(to: CGPoint(x: 47, y: 50))
        center.addEllipse(in: CGRect(x: 41, y: 19, width: 12, height: 12))
        context.stroke(center, with: line, lineWidth: 0.3)
        for left in [true, false] {
            let baseline: CGFloat = left ? 0 : 94, dir: CGFloat = left ? 1 : -1
            let hoop = CGPoint(x: baseline + dir * 5.25, y: 25)
            // Painted key, free-throw circle, three-point line, rim.
            let key = CGRect(x: left ? 0 : 94 - 19, y: 17, width: 19, height: 16)
            context.fill(Path(key), with: .color((left ? game.away.team.color : game.home.team.color).opacity(0.45)))
            context.stroke(Path(key), with: line, lineWidth: 0.3)
            context.stroke(Path(ellipseIn: CGRect(x: baseline + dir * 19 - 6, y: 19, width: 12, height: 12)), with: line, lineWidth: 0.3)
            var three = Path()
            three.move(to: CGPoint(x: baseline, y: 3)); three.addLine(to: CGPoint(x: baseline + dir * 14, y: 3))
            three.addArc(center: hoop, radius: 23.75, startAngle: .degrees(left ? -67.9 : 247.9),
                         endAngle: .degrees(left ? 67.9 : 112.1), clockwise: !left)
            three.addLine(to: CGPoint(x: baseline, y: 47))
            context.stroke(three, with: line, lineWidth: 0.3)
            context.stroke(Path(ellipseIn: CGRect(x: hoop.x - 0.75, y: hoop.y - 0.75, width: 1.5, height: 1.5)), with: .color(.orange), lineWidth: 0.35)
        }
    }

    /// Where a shot was taken on the 94 × 50 ft court: distance out from the team's basket line becomes
    /// left-to-right position, the away team shooting at the left basket and the home team at the right.
    private func spot(_ shot: Play) -> (point: CGPoint, team: Team)? {
        guard let location = shot.location, let team = team(of: shot, in: game) else { return nil }
        let away = team.id == game.away.team.id
        return (CGPoint(x: away ? location.y * 47 : 94 - location.y * 47, y: location.x * 50), team)
    }

    /// The last made basket's flight: an arc from the spot to the rim, with a ring on the spot.
    private func drawLastBasket(_ context: inout GraphicsContext) {
        guard let shot = shots.last(where: \.isScoring), let (point, team) = spot(shot) else { return }
        let hoop = CGPoint(x: team.id == game.away.team.id ? 5.25 : 88.75, y: 25)
        let distance = hypot(hoop.x - point.x, hoop.y - point.y)
        // Bow the line "up" the screen in proportion to its length, so it reads as the ball's flight.
        let control = CGPoint(x: (point.x + hoop.x) / 2, y: min(point.y, hoop.y) - max(2, distance * 0.35))
        var arc = Path()
        arc.move(to: point)
        arc.addQuadCurve(to: hoop, control: control)
        context.stroke(arc, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        context.stroke(arc, with: .color(team.color.mix(with: .white, by: 0.2)), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
        let ring = CGRect(x: point.x - 1.4, y: point.y - 1.4, width: 2.8, height: 2.8)
        context.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: 0.3)
    }

    private func drawShots(_ context: inout GraphicsContext) {
        for shot in shots {
            guard let (point, team) = spot(shot) else { continue }
            let dot = CGRect(x: point.x - 0.8, y: point.y - 0.8, width: 1.6, height: 1.6)
            if shot.isScoring {
                context.fill(Path(ellipseIn: dot), with: .color(team.color))
                context.stroke(Path(ellipseIn: dot), with: .color(.white.opacity(0.8)), lineWidth: 0.15)
            } else {
                context.stroke(Path(ellipseIn: dot), with: .color(team.color.mix(with: .white, by: 0.3)), lineWidth: 0.3)
            }
        }
    }
}

// MARK: - Hockey

/// Rink with every shot and goal where it was taken: goals filled with a ring, shots on goal filled, missed and
/// blocked hollow. Drawn in feet (200 × 85), as ESPN places them (teams change ends each period).
struct HockeyRinkView: View {
    let game: Game
    let plays: [Play]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                legend(game.away.team)
                Spacer()
                legend(game.home.team)
            }
            ZStack {
                Canvas { context, size in
                    let scale = size.width / 200
                    context.scaleBy(x: scale, y: scale)
                    drawRink(&context)
                }
                // The home team's logo at centre ice, under the shots.
                GeometryReader { proxy in
                    TeamLogo(team: game.home.team, size: proxy.size.height * 0.3)
                        .opacity(0.8)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                Canvas { context, size in
                    let scale = size.width / 200
                    context.scaleBy(x: scale, y: scale)
                    drawShots(&context)
                }
                if let shot = plays.last, let location = shot.location, let team = team(of: shot, in: game) {
                    LastShotPulse(point: CGPoint(x: location.x * 200, y: location.y * 85), color: team.color,
                                  made: isGoal(shot), units: 200, onLight: true)
                        .id(shot.id)
                }
            }
            .aspectRatio(200 / 85, contentMode: .fit)
            .rotation3DEffect(.degrees(20), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shot map. " + [game.away.team, game.home.team].map { "\($0.shortName) \(goals($0)) goals on \(onGoal($0)) shots" }.joined(separator: ", "))
    }

    private func isGoal(_ play: Play) -> Bool { (play.type ?? "").lowercased().contains("goal") && play.isScoring }
    private func goals(_ team: Team) -> Int { plays.filter { $0.teamID == team.id && isGoal($0) }.count }
    private func onGoal(_ team: Team) -> Int {
        plays.filter { play in
            let type = (play.type ?? "").lowercased()
            return play.teamID == team.id && (isGoal(play) || (type.contains("shot") && !type.contains("miss") && !type.contains("block")))
        }.count
    }

    private func legend(_ team: Team) -> some View {
        LegendItem(team: team, text: "\(goals(team)) G · \(onGoal(team)) SOG")
    }

    private func drawRink(_ context: inout GraphicsContext) {
        let ice = Path(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 85), cornerRadius: 28)
        context.fill(ice, with: .color(Color(red: 0.93, green: 0.96, blue: 0.99)))
        context.stroke(ice, with: .color(.gray), lineWidth: 0.8)
        let red = Color(red: 0.85, green: 0.15, blue: 0.15), blue = Color(red: 0.15, green: 0.3, blue: 0.8)
        func vertical(_ x: CGFloat, _ color: Color, _ width: CGFloat) {
            var path = Path(); path.move(to: CGPoint(x: x, y: 1)); path.addLine(to: CGPoint(x: x, y: 84))
            context.stroke(path, with: .color(color), lineWidth: width)
        }
        vertical(100, red, 1)
        vertical(75, blue, 1.2)
        vertical(125, blue, 1.2)
        vertical(11, red, 0.4)
        vertical(189, red, 0.4)
        context.stroke(Path(ellipseIn: CGRect(x: 85, y: 27.5, width: 30, height: 30)), with: .color(blue), lineWidth: 0.4)
        for x: CGFloat in [31, 169] {
            for y: CGFloat in [20.5, 64.5] {
                context.stroke(Path(ellipseIn: CGRect(x: x - 15, y: y - 15, width: 30, height: 30)), with: .color(red), lineWidth: 0.4)
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(red))
            }
        }
        // Goal creases.
        for (x, start) in [(CGFloat(11), Angle.degrees(-90)), (CGFloat(189), Angle.degrees(90))] {
            var crease = Path()
            crease.addArc(center: CGPoint(x: x, y: 42.5), radius: 6, startAngle: start, endAngle: start + .degrees(180), clockwise: false)
            context.fill(crease, with: .color(blue.opacity(0.35)))
        }
    }

    private func drawShots(_ context: inout GraphicsContext) {
        for play in plays {
            guard let location = play.location, let team = team(of: play, in: game) else { continue }
            let point = CGPoint(x: location.x * 200, y: location.y * 85)
            let type = (play.type ?? "").lowercased()
            if isGoal(play) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(team.color))
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)), with: .color(team.color), lineWidth: 0.8)
            } else if type.contains("miss") || type.contains("block") {
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)), with: .color(team.color.opacity(0.7)), lineWidth: 0.6)
            } else {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)), with: .color(team.color.opacity(0.9)))
            }
        }
    }
}

/// ESPN's basket behind a baseline: a padded stanchion box in the home team's colour (lit front, shaded side,
/// pale top), a braced grey arm out to a backboard seen edge-on, a bracket, a red-orange rim and a
/// cross-hatched net tapering below. Faces right; mirror for the right-hand end.
private struct Hoop: View {
    let padColor: Color

    var body: some View {
        Canvas { context, size in
            // Drawn on a 50 × 100 grid, scaled to the frame.
            context.scaleBy(x: size.width / 50, y: size.height / 100)
            func fill(_ points: [CGPoint], _ color: Color) {
                var path = Path(); path.addLines(points); path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            // Shadow on the floor, then the stanchion box: front, side and top faces.
            context.fill(Path(ellipseIn: CGRect(x: 0, y: 95, width: 24, height: 5)), with: .color(.black.opacity(0.25)))
            fill([CGPoint(x: 2, y: 50), CGPoint(x: 14, y: 46), CGPoint(x: 14, y: 98), CGPoint(x: 2, y: 98)], padColor)
            fill([CGPoint(x: 14, y: 46), CGPoint(x: 19, y: 48), CGPoint(x: 19, y: 96), CGPoint(x: 14, y: 98)], padColor.mix(with: .black, by: 0.35))
            fill([CGPoint(x: 2, y: 50), CGPoint(x: 14, y: 46), CGPoint(x: 19, y: 48), CGPoint(x: 7, y: 52)], padColor.mix(with: .white, by: 0.3))
            // A seam across the pad, as on the real padding.
            context.stroke(Path { $0.move(to: CGPoint(x: 2, y: 72)); $0.addLine(to: CGPoint(x: 14, y: 70)) },
                           with: .color(.black.opacity(0.18)), lineWidth: 0.8)
            // Arm out to the backboard, light on top and darker underneath, with a diagonal brace.
            fill([CGPoint(x: 9, y: 47), CGPoint(x: 31, y: 39), CGPoint(x: 31, y: 42), CGPoint(x: 9, y: 50)], Color(white: 0.88))
            fill([CGPoint(x: 9, y: 50), CGPoint(x: 31, y: 42), CGPoint(x: 31, y: 43.5), CGPoint(x: 9, y: 51.5)], Color(white: 0.62))
            context.stroke(Path { $0.move(to: CGPoint(x: 17, y: 60)); $0.addLine(to: CGPoint(x: 30, y: 44)) },
                           with: .color(Color(white: 0.7)), lineWidth: 1.5)
            // Backboard, edge-on: a grey back edge and a white face, standing above the arm.
            fill([CGPoint(x: 29, y: 8), CGPoint(x: 31, y: 7), CGPoint(x: 31, y: 47), CGPoint(x: 29, y: 48)], Color(white: 0.72))
            fill([CGPoint(x: 31, y: 7), CGPoint(x: 35, y: 5), CGPoint(x: 35, y: 45), CGPoint(x: 31, y: 47)], .white)
            // Bracket holding the rim off the board.
            fill([CGPoint(x: 35, y: 40), CGPoint(x: 38, y: 40), CGPoint(x: 38, y: 43), CGPoint(x: 35, y: 44)], Color(white: 0.6))
            // Net: strands tapering from the rim, cross-hatched, then the rim on top.
            let rim = CGRect(x: 36, y: 39.5, width: 14, height: 5)
            let topY = rim.midY, bottomY = rim.maxY + 11
            let tops = (0...4).map { CGPoint(x: rim.minX + 1.5 + CGFloat($0) * 2.75, y: topY) }
            let bottoms = (0...4).map { CGPoint(x: rim.midX - 3 + CGFloat($0) * 1.5, y: bottomY) }
            var net = Path()
            for (top, bottom) in zip(tops, bottoms) { net.move(to: top); net.addLine(to: bottom) }
            for (index, top) in tops.enumerated() where index < 4 {
                net.move(to: top); net.addLine(to: bottoms[index + 1])
                net.move(to: tops[index + 1]); net.addLine(to: bottoms[index])
            }
            net.move(to: bottoms[0]); net.addLine(to: bottoms[4])
            context.stroke(net, with: .color(Color(white: 0.85)), lineWidth: 0.6)
            context.stroke(Path(ellipseIn: rim), with: .color(Color(red: 0.95, green: 0.33, blue: 0.15)), lineWidth: 1.6)
        }
        .frame(width: 34, height: 68)
        .accessibilityHidden(true)
    }
}

// MARK: - Soccer

/// Soccer's game cast surface, styled like the football field: the info row above, a tilted pitch with each
/// team's colour and code behind the goal it defends (away on the left, as in the score header), the home logo
/// in the centre circle, and every shot marked by how it ended. Pitch drawn in metres (105 × 68).
struct SoccerPitchView: View {
    let game: Game
    let shots: [Shot]
    let teamStats: [TeamStat]

    /// nil shows the whole match.
    @State private var half: Int?
    @State private var shooter: String?

    /// Each end's team band, as a share of the pitch length (the football field's end zones are 1/10).
    private static let band = 0.08

    private var shown: [Shot] {
        shots.filter { (half == nil || $0.period == half) && (shooter == nil || $0.shooter == shooter) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                GamecastStat(title: "Shots", value: pair { shots in shots.count })
                Divider().frame(height: 34)
                GamecastStat(title: "On Target", value: pair { shots in shots.filter { [.goal, .save].contains($0.outcome) }.count })
                Divider().frame(height: 34)
                GamecastStat(title: "Possession", value: possession)
            }
            .padding(.bottom, 4)
            pitch
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Shot map: " + Shot.Outcome.allCases.map { outcome in
                    "\(shown.filter { $0.outcome == outcome }.count) \(outcome.title.lowercased())"
                }.joined(separator: ", "))
            HStack {
                Picker("Half", selection: $half) {
                    Text("All").tag(Int?.none)
                    Text("1st Half").tag(Int?.some(1))
                    Text("2nd Half").tag(Int?.some(2))
                }
                .pickerStyle(.segmented).fixedSize()
                Spacer()
                Picker("Player", selection: $shooter) {
                    Text("All Players").tag(String?.none)
                    ForEach(Array(Set(shots.compactMap(\.shooter))).sorted(), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .fixedSize()
            }
            .labelsHidden()
            .controlSize(.small)
            HStack(spacing: 6) {
                ForEach(Shot.Outcome.allCases, id: \.self) { outcome in
                    HStack(spacing: 5) {
                        ShotMarker(outcome: outcome)
                        Text(outcome.title).font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.1), in: .capsule)
                }
            }
        }
    }

    private var pitch: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let size = geometry.size, bandWidth = size.width * Self.band / (1 + 2 * Self.band)
                let field = CGRect(x: bandWidth, y: 0, width: size.width - 2 * bandWidth, height: size.height)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        game.away.team.backdropColor.frame(width: bandWidth)
                        Canvas { context, size in
                            context.scaleBy(x: size.width / 105, y: size.height / 68)
                            drawPitch(&context)
                        }
                        game.home.team.backdropColor.frame(width: bandWidth)
                    }
                    EndZoneName(name: game.away.team.abbreviation, angle: -90).frame(width: bandWidth, height: size.height)
                    EndZoneName(name: game.home.team.abbreviation, angle: 90).frame(width: bandWidth, height: size.height)
                        .offset(x: size.width - bandWidth)
                    // The home team's logo in the centre circle, under the shots, as at the football field's midfield.
                    TeamLogo(team: game.home.team, size: size.height * 0.24)
                        .opacity(0.8)
                        .position(x: size.width / 2, y: size.height / 2)
                    // Each goal arcs from where it was struck to where it crossed the line, like a thrown pass.
                    Path { path in
                        for shot in shown where shot.outcome == .goal {
                            guard let end = shot.end else { continue }
                            let from = point(shot.location, team: shot.teamID, in: field)
                            let to = point(end, team: shot.teamID, in: field)
                            path.move(to: from)
                            path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2,
                                                                       y: min(from.y, to.y) - max(14, abs(to.x - from.x) * 0.35)))
                        }
                    }
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
                    // Goals last, so they sit on top of nearby misses.
                    ForEach(shown.sorted { ($0.outcome == .goal ? 1 : 0) < ($1.outcome == .goal ? 1 : 0) }) { shot in
                        ShotMarker(outcome: shot.outcome)
                            .position(point(shot.location, team: shot.teamID, in: field))
                            .help(shot.text)
                    }
                }
            }
            .aspectRatio((1 + 2 * Self.band) * 105 / 68, contentMode: .fit)
            // The pitch's front edge in each team's colour at its end, for the football field's raised look.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    game.away.team.backdropColor.frame(width: geometry.size.width * Self.band / (1 + 2 * Self.band))
                    Color.turfDark
                    game.home.team.backdropColor.frame(width: geometry.size.width * Self.band / (1 + 2 * Self.band))
                }
            }
            .brightness(-0.25)
            .frame(height: 7)
        }
        .clipShape(.rect(cornerRadius: 8))
        .rotation3DEffect(.degrees(22), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        // Real pitch proportions, at most 260pt tall. Capped by width so the front edge stays as wide as the pitch.
        .frame(maxWidth: 260 * (1 + 2 * Self.band) * 105 / 68)
    }

    /// "away–home" for a count over each team's shown shots.
    private func pair(_ count: ([Shot]) -> Int) -> String {
        "\(count(shown.filter { $0.teamID == game.away.team.id }))–\(count(shown.filter { $0.teamID == game.home.team.id }))"
    }

    /// The whole match's possession, from the team stats.
    private var possession: String? {
        teamStats.first { $0.label.localizedCaseInsensitiveCompare("Possession") == .orderedSame }
            .map { "\($0.away)–\($0.home)%" }
    }

    /// Shots come in the shooter's attacking frame. Away defends the left goal, so it shoots right; home is turned to face left.
    private func point(_ location: Play.Location, team: Team.ID, in field: CGRect) -> CGPoint {
        let away = team == game.away.team.id
        return CGPoint(x: field.minX + (away ? location.x : 1 - location.x) * field.width,
                       y: field.minY + (away ? location.y : 1 - location.y) * field.height)
    }

    private func drawPitch(_ context: inout GraphicsContext) {
        for stripe in 0..<6 {
            context.fill(Path(CGRect(x: CGFloat(stripe) * 17.5, y: 0, width: 17.5, height: 68)),
                         with: .color(stripe.isMultiple(of: 2) ? Color.turfDark : Color.turfLight))
        }
        let line = GraphicsContext.Shading.color(.white.opacity(0.85))
        context.stroke(Path(CGRect(x: 0, y: 0, width: 105, height: 68)), with: line, lineWidth: 0.4)
        var half = Path(); half.move(to: CGPoint(x: 52.5, y: 0)); half.addLine(to: CGPoint(x: 52.5, y: 68))
        half.addEllipse(in: CGRect(x: 52.5 - 9.15, y: 34 - 9.15, width: 18.3, height: 18.3))
        context.stroke(half, with: line, lineWidth: 0.4)
        for left in [true, false] {
            let x: CGFloat = left ? 0 : 105, dir: CGFloat = left ? 1 : -1
            context.stroke(Path(CGRect(x: left ? 0 : 105 - 16.5, y: 34 - 20.15, width: 16.5, height: 40.3)), with: line, lineWidth: 0.4)
            context.stroke(Path(CGRect(x: left ? 0 : 105 - 5.5, y: 34 - 9.15, width: 5.5, height: 18.3)), with: line, lineWidth: 0.4)
            context.fill(Path(ellipseIn: CGRect(x: x + dir * 11 - 0.4, y: 33.6, width: 0.8, height: 0.8)), with: line)
        }
    }
}

/// ESPN's shot icons: a white disc showing how the shot ended.
private struct ShotMarker: View {
    let outcome: Shot.Outcome

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(.black.opacity(0.75), lineWidth: 1.3)
            switch outcome {
            case .goal: Image(systemName: "soccerball").font(.system(size: 14, weight: .semibold))
            case .save: Image(systemName: "nosign").font(.system(size: 10, weight: .bold))
            case .block: Circle().frame(width: 5, height: 5)
            case .offTarget: EmptyView()
            }
        }
        .foregroundStyle(.black.opacity(0.8))
        // Goals a size up, as on ESPN, so they stand out from the misses.
        .frame(width: outcome == .goal ? 20 : 16, height: outcome == .goal ? 20 : 16)
        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }
}

extension Shot.Outcome {
    var title: String {
        switch self {
        case .goal: "Goal"
        case .save: "Save"
        case .offTarget: "Off Target"
        case .block: "Block"
        }
    }
}
