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
                    BaseballDiamondView(game: game, plays: detail?.plays ?? []).frame(maxWidth: 460)
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

/// ESPN's Gamecast diamond: count and outs, runners on base, and the latest batted ball arcing to where it landed.
/// Drawn in ESPN's 250-unit hit-chart space, with home plate at (125, 204).
struct BaseballDiamondView: View {
    let game: Game
    let plays: [Play]

    private static let home = CGPoint(x: 125, y: 204)
    private static let first = CGPoint(x: 152.7, y: 176.3)
    private static let second = CGPoint(x: 125, y: 148.6)
    private static let third = CGPoint(x: 97.3, y: 176.3)

    var body: some View {
        let state = game.status == .live ? game.situation?.baseball : nil
        VStack(spacing: 10) {
            if let state {
                HStack(spacing: 22) {
                    count("Balls", state.balls, of: 4)
                    count("Strikes", state.strikes, of: 3)
                    count("Outs", state.outs, of: 3)
                }
            }
            Canvas { context, size in
                // The field runs from the fence (y ≈ 30) to behind home plate (y ≈ 215).
                let scale = min(size.width / 250, size.height / 192)
                context.translateBy(x: (size.width - 250 * scale) / 2, y: -26 * scale)
                context.scaleBy(x: scale, y: scale)
                drawField(&context)
                drawBases(&context, state: state)
                drawHits(&context)
            }
            .frame(height: 270)
            .rotation3DEffect(.degrees(30), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            if let state, state.batter != nil || state.pitcher != nil {
                Text([state.batter.map { "At bat: \($0)" }, state.pitcher.map { "Pitching: \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(state))
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

    private func count(_ title: String, _ value: Int, of total: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(0..<(total - 1), id: \.self) { index in
                Circle()
                    .fill(index < value ? (title == "Outs" ? Color.red : Color.green) : Color.clear)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5)))
                    .frame(width: 11, height: 11)
            }
        }
    }

    private func point(_ location: Play.Location) -> CGPoint {
        CGPoint(x: location.x * 250, y: location.y * 250)
    }

    private func drawField(_ context: inout GraphicsContext) {
        let home = Self.home
        // Outfield grass out to the fence, between the foul lines, with a warning track.
        var fan = Path()
        fan.move(to: home)
        fan.addLine(to: CGPoint(x: home.x - 118, y: home.y - 118))
        fan.addQuadCurve(to: CGPoint(x: home.x + 118, y: home.y - 118), control: CGPoint(x: home.x, y: home.y - 230))
        fan.closeSubpath()
        context.fill(fan, with: .color(Color(red: 0.62, green: 0.48, blue: 0.32)))
        var grass = Path()
        grass.move(to: home)
        grass.addLine(to: CGPoint(x: home.x - 112, y: home.y - 112))
        grass.addQuadCurve(to: CGPoint(x: home.x + 112, y: home.y - 112), control: CGPoint(x: home.x, y: home.y - 220))
        grass.closeSubpath()
        context.fill(grass, with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.55, blue: 0.22), Color(red: 0.28, green: 0.65, blue: 0.28)]),
                                                  startPoint: CGPoint(x: home.x, y: home.y - 200), endPoint: home))
        // Infield dirt arc and the grass square inside the bases.
        var dirt = Path()
        dirt.move(to: home)
        dirt.addLine(to: CGPoint(x: home.x - 50, y: home.y - 50))
        dirt.addQuadCurve(to: CGPoint(x: home.x + 50, y: home.y - 50), control: CGPoint(x: home.x, y: home.y - 98))
        dirt.closeSubpath()
        context.fill(dirt, with: .color(Color(red: 0.76, green: 0.58, blue: 0.38)))
        var square = Path()
        square.move(to: CGPoint(x: home.x, y: home.y - 6))
        square.addLine(to: CGPoint(x: Self.first.x - 6, y: Self.first.y))
        square.addLine(to: CGPoint(x: Self.second.x, y: Self.second.y + 6))
        square.addLine(to: CGPoint(x: Self.third.x + 6, y: Self.third.y))
        square.closeSubpath()
        context.fill(square, with: .color(Color(red: 0.26, green: 0.62, blue: 0.27)))
        // Foul lines and the mound.
        var lines = Path()
        lines.move(to: CGPoint(x: home.x - 112, y: home.y - 112)); lines.addLine(to: home)
        lines.addLine(to: CGPoint(x: home.x + 112, y: home.y - 112))
        context.stroke(lines, with: .color(.white.opacity(0.85)), lineWidth: 0.8)
        context.fill(Path(ellipseIn: CGRect(x: 120, y: 172, width: 10, height: 10)), with: .color(Color(red: 0.76, green: 0.58, blue: 0.38)))
        context.fill(Path(ellipseIn: CGRect(x: home.x - 9, y: home.y - 7, width: 18, height: 12)), with: .color(Color(red: 0.76, green: 0.58, blue: 0.38)))
    }

    private func drawBases(_ context: inout GraphicsContext, state: Game.Situation.Baseball?) {
        let occupied = [state?.onFirst ?? false, state?.onSecond ?? false, state?.onThird ?? false]
        for (index, base) in [Self.first, Self.second, Self.third].enumerated() {
            let diamond = Path { path in
                path.move(to: CGPoint(x: base.x, y: base.y - 4)); path.addLine(to: CGPoint(x: base.x + 4, y: base.y))
                path.addLine(to: CGPoint(x: base.x, y: base.y + 4)); path.addLine(to: CGPoint(x: base.x - 4, y: base.y))
                path.closeSubpath()
            }
            context.fill(diamond, with: .color(occupied[index] ? Color(red: 0.2, green: 0.45, blue: 1) : .white))
        }
        context.fill(Path(ellipseIn: CGRect(x: Self.home.x - 2.5, y: Self.home.y - 2.5, width: 5, height: 5)), with: .color(.white))
    }

    private func drawHits(_ context: inout GraphicsContext) {
        let atBats = atBats
        // Earlier batted balls as dots; the latest at-bat gets the flight line, but only if it was put in play.
        for (play, location) in atBats.dropLast().compactMap({ at in at.spot.map { (at.play, $0) } }).suffix(7) {
            let spot = point(location)
            let dot = Path(ellipseIn: CGRect(x: spot.x - 2, y: spot.y - 2, width: 4, height: 4))
            context.fill(dot, with: .color((team(of: play, in: game)?.color ?? .white).opacity(0.85)))
            context.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 0.6)
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
        // A white casing under the dark line keeps it readable over dark backgrounds as well as the grass.
        context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        context.stroke(path, with: .color(.black.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        context.stroke(Path(ellipseIn: CGRect(x: spot.x - 7, y: spot.y - 4, width: 14, height: 8)), with: .color(.green), lineWidth: 2.5)
        context.fill(Path(ellipseIn: CGRect(x: spot.x - 3, y: spot.y - 2, width: 6, height: 4)), with: .color(.blue))
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
