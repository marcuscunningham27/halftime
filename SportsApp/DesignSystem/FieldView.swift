import SportsKit
import SwiftUI

/// One play drawn on the field, like the ESPN and iOS drive charts.
struct PlayMark: Hashable {
    enum Kind { case run, pass, incomplete, loss, penalty }

    let start: Int
    let end: Int
    let kind: Kind

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
        guard game.league == .nfl else { return nil }
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
                        game.away.team.color.frame(width: width / 12)
                        ForEach(0..<10) { i in
                            (i.isMultiple(of: 2) ? Color.turfLight : Color.turfDark).frame(maxWidth: .infinity)
                        }
                        game.home.team.color.frame(width: width / 12)
                    }
                    // Team names painted in the end zones, reading toward midfield like a real field.
                    endZoneName(game.away.team.abbreviation, angle: -90).frame(width: width / 12, height: height)
                    endZoneName(game.home.team.abbreviation, angle: 90).frame(width: width / 12, height: height)
                        .offset(x: width * 11 / 12)
                    ForEach(1..<10) { i in
                        Rectangle().fill(.white.opacity(i == 5 ? 0.55 : 0.25)).frame(width: 1, height: height)
                            .offset(x: x(i * 10, width) - 0.5)
                    }
                    // The home team's logo at midfield, under the drive.
                    TeamLogo(team: game.home.team, size: height * 0.42)
                        .opacity(0.8)
                        .position(x: width / 2, y: height / 2)
                    if let gain = state.lineToGain {
                        Rectangle().fill(.yellow).frame(width: 2, height: height).offset(x: x(gain, width) - 1)
                    }
                    Canvas { context, size in
                        draw(in: &context, size: size)
                    }
                    Image(systemName: "football.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, offenseColor)
                        .background { BallPulse(color: offenseColor) }
                        .position(x: x(state.ball, width), y: rowY(state.marks.count, height))
                }
                // The ball and line to gain slide to their new spots after each snap.
                .animation(.spring(duration: 0.8), value: state.ball)
                .animation(.spring(duration: 0.8), value: state.lineToGain)
            }
            .frame(height: 120)
            // The field's front edge, for ESPN's raised look.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    game.away.team.color.frame(width: geometry.size.width / 12)
                    Color.turfDark
                    game.home.team.color.frame(width: geometry.size.width / 12)
                }
            }
            .brightness(-0.25)
            .frame(height: 7)
            }
            .clipShape(.rect(cornerRadius: 8))
            .rotation3DEffect(.degrees(22), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            // Goalposts stand upright, so they sit outside the tilt, just behind each end line.
            .overlay(alignment: .leading) { Goalpost().offset(x: 4, y: -40) }
            .overlay(alignment: .trailing) { Goalpost().offset(x: -4, y: -40) }
            .padding(.top, 28)

            // ESPN's markers under the field: team, 20, 50, 20, team.
            GeometryReader { geometry in
                let width = geometry.size.width
                ForEach([(10, game.home.team.abbreviation), (20, "20"), (50, "50"), (80, "20"), (110, game.away.team.abbreviation)], id: \.0) { yard, label in
                    Text(label)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(yard == 10 || yard == 110 ? .primary : .secondary)
                        .fixedSize()
                        .position(x: x(yard == 10 ? -5 : yard == 110 ? 105 : yard, width), y: 7)
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([state.down, state.ballOn.map { "ball on \($0)" }, state.drive, state.lastPlay?.text].compactMap { $0 }.joined(separator: ", "))
    }

    /// DOWN | BALL ON | DRIVE, as ESPN's Gamecast heads the field.
    private var header: some View {
        HStack(spacing: 0) {
            stat("Down", state.down)
            Divider().frame(height: 34)
            stat("Ball On", state.ballOn)
            Divider().frame(height: 34)
            stat("Drive", state.drive)
        }
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 2) {
            Text(title + ":").font(.caption.weight(.medium)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value ?? "–").font(.title3.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func endZoneName(_ name: String, angle: Double) -> some View {
        Text(name)
            .font(.system(size: 13, weight: .heavy).width(.expanded))
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize()
            .rotationEffect(.degrees(angle))
    }

    /// Plays stack from the top of the field down, oldest first; the ball sits on the row after the last.
    private func rowY(_ index: Int, _ height: CGFloat) -> CGFloat {
        let rows = max(state.marks.count + 1, 4)
        // Room above the first row for its pass arc.
        let top: CGFloat = 18, bottom: CGFloat = 8
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
private struct Goalpost: View {
    var body: some View {
        Canvas { context, size in
            let mid = size.width / 2, bar: CGFloat = 26
            var path = Path()
            path.move(to: CGPoint(x: mid, y: size.height))
            path.addLine(to: CGPoint(x: mid, y: bar))
            path.move(to: CGPoint(x: mid - 3, y: bar))
            path.addLine(to: CGPoint(x: mid + 3, y: bar))
            path.move(to: CGPoint(x: mid - 3, y: bar))
            path.addLine(to: CGPoint(x: mid - 3, y: 0))
            path.move(to: CGPoint(x: mid + 3, y: bar))
            path.addLine(to: CGPoint(x: mid + 3, y: 0))
            context.stroke(path, with: .color(Color(red: 0.98, green: 0.82, blue: 0.2)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .frame(width: 10, height: 64)
        .accessibilityHidden(true)
    }
}
