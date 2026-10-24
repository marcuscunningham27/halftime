import SportsKit
import SwiftUI

/// One play drawn on the field, like the ESPN and iOS drive charts.
struct PlayMark: Hashable {
    enum Kind { case run, pass, incomplete, loss, penalty }

    let start: Int
    let end: Int
    let kind: Kind
    /// The snap itself, for its yardage.
    let play: Play

    /// Reads ESPN's play type; kicks, timeouts and period markers aren't drawn.
    init?(_ play: Play) {
        guard let start = play.startYardLine, let type = play.type?.lowercased() else { return nil }
        let end = play.endYardLine ?? start
        switch true {
        case type.contains("pass") && type.contains("incomplet"): kind = .incomplete
        case type.contains("pass") || type.contains("interception"): kind = .pass
        case type.contains("sack"): kind = .loss
        case type.contains("rush") || type.contains("run") || type.contains("scramble"): kind = .run
        case type.contains("penalty"): kind = .penalty
        default: return nil
        }
        self.start = start
        self.end = end
        self.play = play
    }
}

/// What the field shows: from the live situation, or from the last drive once the game is over.
struct FieldState {
    /// Yards from the home goal line.
    let ball: Int
    let offenseTeamID: Team.ID?
    let lineToGain: Int?
    /// This drive's plays, oldest first.
    let marks: [PlayMark]
    /// ESPN's header over the field: "1st & 10", "NE 34", "1 play, 14 yds".
    let down: String?
    let ballOn: String?
    let drive: String?
    /// The snap shown under the field, "Last play: 1st & 10 at NE 20" and its description.
    let lastPlay: Play?

    /// Snaps carry a down-and-distance spot; markers like "End of Game" don't.
    private static func isSnap(_ play: Play) -> Bool { play.spot != nil && (play.endYardLine ?? play.startYardLine) != nil }

    /// "13 plays, 61 yards, 5:46" → "13 plays, 61 yds", as ESPN shortens it.
    private static func shortDrive(_ summary: String?) -> String? {
        guard let summary, !summary.isEmpty else { return nil }
        return summary.components(separatedBy: ", ").prefix(2).joined(separator: ", ")
            .replacingOccurrences(of: "yards", with: "yds").replacingOccurrences(of: "yard", with: "yd")
    }

    init?(game: Game, detail: GameDetail?) {
        guard [.nfl, .cfb].contains(game.league) else { return nil }
        if game.status == .live, let situation = game.situation, let ball = situation.yardLine {
            self.ball = ball
            offenseTeamID = situation.possessionTeamID
            lineToGain = situation.distance.map { distance in
                // The home offence moves toward the away goal (yard line rising), the away offence the other way.
                min(100, max(0, situation.possessionTeamID == game.home.team.id ? ball + distance : ball - distance))
            }
            let drive = detail?.drives.last.flatMap { $0.teamID == situation.possessionTeamID ? $0 : nil }
            marks = drive?.plays.compactMap(PlayMark.init) ?? []
            // "1st & 10 · BUF 18"
            let parts = situation.shortDownAndDistance?.components(separatedBy: " · ") ?? []
            down = parts.first
            ballOn = parts.count > 1 ? parts[1] : nil
            self.drive = Self.shortDrive(drive?.summary)
            lastPlay = drive?.plays.last(where: Self.isSnap)
            return
        }
        // After the whistle (or between snaps without a situation), show where the last snap ended, as iOS does.
        guard let drive = detail?.drives.last(where: { $0.plays.contains(where: Self.isSnap) }),
              let last = drive.plays.last(where: Self.isSnap),
              let ball = last.endYardLine ?? last.startYardLine
        else { return nil }
        self.ball = ball
        offenseTeamID = drive.teamID
        lineToGain = nil
        marks = drive.plays.compactMap(PlayMark.init)
        // "3rd & 22 at SF 40": the last snap's down and spot.
        let parts = last.spot?.components(separatedBy: " at ") ?? []
        down = parts.first
        ballOn = parts.count > 1 ? parts[1] : nil
        self.drive = Self.shortDrive(drive.summary)
        lastPlay = last
    }
}

/// A tilted football field with the drive drawn on it: one row per play, straight lines for runs,
/// arcs for passes (dashed when incomplete), red for losses, the ball and the line to gain.
/// Away end zone on the left, home on the right, matching the score layout.
struct FieldView: View {
    let game: Game
    let state: FieldState

    var body: some View {
        VStack(spacing: 6) {
            header.padding(.bottom, 4)
            VStack(spacing: 0) {
            GeometryReader { geometry in
                let width = geometry.size.width, height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    // ESPN-style grass, mown in 10-yard stripes, end zones in team colours, yard lines every 10.
                    HStack(spacing: 0) {
                        game.away.team.backdropColor.frame(width: width / 12)
                        ForEach(0..<10) { i in
                            (i.isMultiple(of: 2) ? Color.turfLight : Color.turfDark).frame(maxWidth: .infinity)
                        }
                        game.home.team.backdropColor.frame(width: width / 12)
                    }
                    // Team names painted in the end zones, reading toward midfield like a real field.
                    EndZoneName(name: game.away.team.abbreviation, angle: -90).frame(width: width / 12, height: height)
                    EndZoneName(name: game.home.team.abbreviation, angle: 90).frame(width: width / 12, height: height)
                        .offset(x: width * 11 / 12)
                    // The NBA floor's light: brighter at the far left, falling off toward the near right.
                    LinearGradient(colors: [.white.opacity(0.1), .clear, .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Canvas { context, size in drawMarkings(in: &context, size: size) }
                    // Yard numbers painted along both sidelines, the far row upside down as on a real field.
                    ForEach(1..<10) { i in
                        let label = Text("\(min(i, 10 - i) * 10)").font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                        label.position(x: x(i * 10, width), y: height - 16)
                        label.rotationEffect(.degrees(180)).position(x: x(i * 10, width), y: 16)
                    }
                    // The home team's logo at midfield, under the drive.
                    TeamLogo(team: game.home.team, size: height * 0.38)
                        .opacity(0.8)
                        .position(x: width / 2, y: height / 2)
                    // While live, the offence's attacking side is shaded from the ball, as the NBA court shades its half.
                    if game.status == .live, let offense = [game.away.team, game.home.team].first(where: { $0.id == state.offenseTeamID }) {
                        PossessionOverlay(color: offense.color, towardLeft: offense.id == game.home.team.id,
                                          from: x(state.ball, width) / width)
                            .id(offense.id)
                            .transition(.opacity)
                    }
                    // ESPN's lines: blue at the line of scrimmage, yellow at the line to gain.
                    Rectangle().fill(Color(red: 0.25, green: 0.5, blue: 1)).frame(width: 2, height: height).offset(x: x(state.ball, width) - 1)
                    if let gain = state.lineToGain {
                        Rectangle().fill(.yellow).frame(width: 2, height: height).offset(x: x(gain, width) - 1)
                    }
                    Canvas { context, size in
                        draw(in: &context, size: size)
                    }
                    // On the last play's row, so the pin stands on the end of its line with the yardage beneath, as ESPN does.
                    let ball = CGPoint(x: x(state.ball, width), y: rowY(max(state.marks.count - 1, 0), height))
                    if let mark = state.marks.last, let label = yardage(mark) {
                        // ESPN's "+10 Yds" under the end of the last play.
                        Text(label)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(white: 0.9), in: .rect(cornerRadius: 5))
                            .fixedSize()
                            .position(x: x(mark.end, width), y: rowY(state.marks.count - 1, height) + 15)
                    }
                    if let offense = [game.away.team, game.home.team].first(where: { $0.id == state.offenseTeamID }) {
                        // The offence's logo in a pin whose point sits on the ball, as ESPN marks possession.
                        Color.clear.frame(width: 12, height: 12).background { BallPulse(color: offense.color) }
                            .position(ball)
                        PossessionPin(team: offense).position(x: ball.x, y: ball.y - PossessionPin.height / 2)
                    } else {
                        Image(systemName: "football.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, offenseColor)
                            .background { BallPulse(color: offenseColor) }
                            .position(ball)
                    }
                }
                // The ball and lines slide to their new spots after each snap; possession fades across.
                .animation(.spring(duration: 0.8), value: state.ball)
                .animation(.spring(duration: 0.8), value: state.lineToGain)
                .animation(.easeInOut(duration: 0.5), value: state.offenseTeamID)
            }
            .frame(height: 170)
            // The field's front edge, for ESPN's raised look.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    game.away.team.backdropColor.frame(width: geometry.size.width / 12)
                    Color.turfDark
                    game.home.team.backdropColor.frame(width: geometry.size.width / 12)
                }
            }
            .brightness(-0.25)
            .frame(height: 7)
            }
            .clipShape(.rect(cornerRadius: 8))
            // The white boundary the NBA court has.
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .rotation3DEffect(.degrees(22), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            // Goalposts stand upright, so they sit outside the tilt, just behind each end line.
            .overlay(alignment: .leading) { Goalpost().offset(x: -4, y: -52) }
            .overlay(alignment: .trailing) { Goalpost().scaleEffect(x: -1).offset(x: 4, y: -52) }
            .padding(.top, 28)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([state.down, state.ballOn.map { "ball on \($0)" }, state.drive, state.lastPlay?.text].compactMap { $0 }.joined(separator: ", "))
    }

    /// DOWN | BALL ON | DRIVE, as ESPN's Gamecast heads the field.
    private var header: some View {
        HStack(spacing: 0) {
            GamecastStat(title: "Down", value: state.down)
            Divider().frame(height: 34)
            GamecastStat(title: "Ball On", value: state.ballOn)
            Divider().frame(height: 34)
            GamecastStat(title: "Drive", value: state.drive)
        }
    }

    /// Yard lines every 5 (brighter every 10, brightest at midfield), and a tick each yard along both hash rows.
    private func drawMarkings(in context: inout GraphicsContext, size: CGSize) {
        for yard in stride(from: 5, through: 95, by: 5) {
            let lineX = x(yard, size.width)
            context.fill(Path(CGRect(x: lineX - 0.5, y: 0, width: 1, height: size.height)),
                         with: .color(.white.opacity(yard == 50 ? 0.6 : yard.isMultiple(of: 10) ? 0.35 : 0.18)))
        }
        for yard in 1..<100 where !yard.isMultiple(of: 5) {
            let tickX = x(yard, size.width)
            for row in [0.36, 0.64] {
                context.fill(Path(CGRect(x: tickX - 0.5, y: size.height * row - 2.5, width: 1, height: 5)), with: .color(.white.opacity(0.3)))
            }
        }
    }

    /// Plays stack from the top of the field down, oldest first.
    private func rowY(_ index: Int, _ height: CGFloat) -> CGFloat {
        let rows = max(state.marks.count, 4)
        // Room above the first row for the possession pin (and any pass arc), and below the last for its yardage label.
        let top = PossessionPin.height + 4, bottom: CGFloat = 28
        return top + (height - top - bottom) * CGFloat(index) / CGFloat(rows - 1)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        for (index, mark) in state.marks.enumerated() {
            let y = rowY(index, size.height)
            let from = CGPoint(x: x(mark.start, size.width), y: y)
            let to = CGPoint(x: x(mark.end, size.width), y: y)
            var path = Path()
            path.move(to: from)
            let color: Color
            var style = StrokeStyle(lineWidth: 2, lineCap: .round)
            switch mark.kind {
            case .pass, .incomplete:
                // Passes arc up between snap and catch (or where the ball fell incomplete, at the line).
                let landing = mark.kind == .incomplete ? CGPoint(x: from.x + (to.x == from.x ? direction * 22 : to.x - from.x), y: y) : to
                path.addQuadCurve(to: landing, control: CGPoint(x: (from.x + landing.x) / 2, y: y - 14))
                color = mark.kind == .incomplete ? .white.opacity(0.5) : offenseColor.mix(with: .white, by: 0.35)
                if mark.kind == .incomplete { style.dash = [3, 3] }
            case .run:
                path.addLine(to: to)
                color = offenseColor.mix(with: .white, by: 0.35)
            case .loss:
                path.addLine(to: to)
                color = .red
            case .penalty:
                path.addLine(to: to)
                color = .yellow.opacity(0.8)
                style.dash = [1, 3]
            }
            context.stroke(path, with: .color(color), style: style)
            context.fill(Path(ellipseIn: CGRect(x: from.x - 2, y: y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.7)))
        }
    }

    /// "+10 Yds", "−3 Yds", "No Gain" or "Incomplete" for a drawn play.
    private func yardage(_ mark: PlayMark) -> String? {
        if mark.kind == .incomplete { return "Incomplete" }
        guard let yards = mark.play.yardsGained(homeOffense: state.offenseTeamID == game.home.team.id) else { return nil }
        return yards == 0 ? "No Gain" : yards > 0 ? "+\(yards) Yds" : "−\(-yards) Yds"
    }

    /// +1 when the offence moves right (the away team, toward the home goal), −1 when it moves left.
    private var direction: CGFloat {
        state.offenseTeamID == game.home.team.id ? -1 : 1
    }

    private var offenseColor: Color {
        state.offenseTeamID == game.home.team.id ? game.home.team.color : game.away.team.color
    }

    /// Horizontal position of a spot measured from the home goal; the field is 120 units including end zones.
    private func x(_ yardsFromHomeGoal: Int, _ width: CGFloat) -> CGFloat {
        width * CGFloat(10 + (100 - yardsFromHomeGoal)) / 120
    }
}

/// ESPN's possession marker: a white map pin with the offence's logo, its point on the ball.
private struct PossessionPin: View {
    static let height: CGFloat = 40
    let team: Team

    var body: some View {
        ZStack(alignment: .top) {
            Pin().fill(.white).shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            Pin().stroke(.black.opacity(0.75), lineWidth: 1.5)
            TeamLogo(team: team, size: 20).padding(.top, 6)
        }
        .frame(width: 32, height: Self.height)
        .accessibilityHidden(true)
    }
}

/// A circle on top narrowing to a point at the bottom. Shapes draw off the main actor.
nonisolated private struct Pin: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2, center = CGPoint(x: rect.midX, y: radius)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// One figure in a game cast's info row, e.g. "DOWN: 3rd & 4" or "SHOTS: 11–13".
struct GamecastStat: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title + ":").font(.caption.weight(.medium)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value ?? "–").font(.title3.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A team's code painted across its end of the field, reading toward the middle.
struct EndZoneName: View {
    let name: String
    let angle: Double

    var body: some View {
        Text(name)
            .font(.system(size: 13, weight: .heavy).width(.expanded))
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize()
            .rotationEffect(.degrees(angle))
    }
}

extension Color {
    static let turfLight = Color(red: 76 / 255, green: 168 / 255, blue: 70 / 255)
    static let turfDark = Color(red: 64 / 255, green: 152 / 255, blue: 60 / 255)
}

/// A ring rippling out from the ball, so the eye finds it.
private struct BallPulse: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            Circle().stroke(color.mix(with: .white, by: 0.4).opacity(1 - t), lineWidth: 1.5)
                .frame(width: 16 + t * 18, height: 16 + t * 18)
        }
        .frame(width: 34, height: 34)
        .allowsHitTesting(false)
    }
}

/// A yellow goalpost seen from the side of the field: post, crossbar and two uprights.
/// ESPN's goalpost, drawn upright behind an end line: a dark stump, a gooseneck curving up into the middle of a
/// crossbar seen at an angle, and two long parallel uprights, all in flat goalpost yellow. Faces right; mirror
/// for the right-hand end.
private struct Goalpost: View {
    var body: some View {
        Canvas { context, size in
            // Drawn on a 36 × 100 grid, scaled to the frame.
            context.scaleBy(x: size.width / 36, y: size.height / 100)
            let yellow = GraphicsContext.Shading.color(Color(red: 0.89, green: 0.79, blue: 0.25))
            let near = CGPoint(x: 10, y: 66), far = CGPoint(x: 26, y: 54)
            var post = Path()
            // Gooseneck: up from the stump, then curving forward into the crossbar's middle.
            post.move(to: CGPoint(x: 6, y: 90))
            post.addLine(to: CGPoint(x: 6, y: 74))
            post.addQuadCurve(to: CGPoint(x: (near.x + far.x) / 2, y: (near.y + far.y) / 2), control: CGPoint(x: 6, y: 62))
            // Crossbar, then the two uprights.
            post.move(to: near); post.addLine(to: far)
            post.move(to: near); post.addLine(to: CGPoint(x: near.x, y: 12))
            post.move(to: far); post.addLine(to: CGPoint(x: far.x, y: 0))
            context.stroke(post, with: yellow, style: StrokeStyle(lineWidth: 3, lineCap: .butt, lineJoin: .round))
            context.fill(Path(roundedRect: CGRect(x: 3, y: 86, width: 6, height: 14), cornerRadius: 2), with: .color(Color(white: 0.35)))
        }
        .frame(width: 36, height: 100)
        .accessibilityHidden(true)
    }
}
