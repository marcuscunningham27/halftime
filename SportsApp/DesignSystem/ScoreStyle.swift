import SportsKit
import SwiftUI

extension Font {
    /// Boxy sports numerals (scores, stat values, leader numbers): Chakra Petch Bold, bundled under
    /// the SIL Open Font License.
    static func score(_ size: CGFloat) -> Font {
        .custom("ChakraPetch-Bold", size: size)
    }

    /// ESPN-style bold condensed labels, e.g. a leaders category or stat name.
    static func scoreLabel(_ style: Font.TextStyle = .subheadline) -> Font {
        .system(style, weight: .bold).width(.condensed)
    }
}

extension Game {
    /// Centre status in iOS style: "4th 1:54", "Half", "Final", or a start time.
    var headlineStatus: String {
        switch status {
        case .scheduled:
            return startDate.formatted(date: .omitted, time: .shortened)
        case .final:
            return statusDetail
        case .live:
            if intermission == .halftime { return "Half" }
            if intermission == .endOfPeriod { return statusDetail }
            switch league.periodStyle {
            case .quarters, .periods:
                let period = self.period <= league.regulationPeriods ? Self.ordinal(self.period) : league.periodLabel(self.period)
                return "\(period) \(clock)"
            case .innings, .halves:
                return statusDetail
            }
        }
    }

    /// Smaller line under the status: down and distance, series state, or nothing.
    var substatus: String? {
        if status == .live, let spot = situation?.shortDownAndDistance { return spot }
        return seriesSummary
    }

    func hasBall(_ competitor: Competitor) -> Bool {
        status == .live && situation?.possessionTeamID == competitor.team.id
    }

    static func ordinal(_ n: Int) -> String {
        let suffix = switch (n % 10, n % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(n)\(suffix)"
    }
}

/// The big iOS Sports score row: logo and name on the outside, compressed scores, status in the middle.
struct ScoreCard: View {
    let game: Game
    /// League-qualified, since team IDs repeat across leagues (NFL 49ers and NHL Ducks are both 25).
    var followed: Set<Follows.TeamRef> = []
    /// Adds the local date under the status, for lists that span days (the Fantasy weeks).
    var showsDate = false

    var body: some View {
        HStack(spacing: 8) {
            side(game.away)
            score(game.away)
            VStack(spacing: 3) {
                if let note = game.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    if game.status == .live {
                        Circle().fill(.red).frame(width: 6, height: 6)
                    }
                    Text(game.headlineStatus)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if showsDate {
                    Text(game.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let sub = game.substatus {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                // Where to watch, for games still to be played or in progress.
                if game.status != .final, !game.broadcasts.isEmpty {
                    Label(game.broadcasts.prefix(2).joined(separator: " · "), systemImage: "tv")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 2)
                        .help(game.broadcasts.joined(separator: ", "))
                }
            }
            .frame(maxWidth: .infinity)
            score(game.home)
            side(game.home)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.accessibilitySummary)
    }

    private func side(_ competitor: Game.Competitor) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                TeamLogo(team: competitor.team, size: 40)
                if followed.contains(.init(leagueID: game.leagueID, teamID: competitor.team.id)) {
                    Image(systemName: "star.fill").font(.system(size: 9)).offset(x: 8, y: -2)
                }
            }
            Text(competitor.team.shortName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96)
    }

    @ViewBuilder
    private func score(_ competitor: Game.Competitor) -> some View {
        HStack(spacing: 4) {
            if game.hasBall(competitor), competitor.team.id == game.home.team.id {
                Image(systemName: "football.fill").font(.caption).foregroundStyle(.secondary)
            }
            Text(competitor.score.map(String.init) ?? competitor.record ?? "")
                .font(competitor.score == nil ? .subheadline : .score(40))
                .monospacedDigit()
                .foregroundStyle(game.isLosing(competitor) || competitor.score == nil ? .secondary : .primary)
            if game.hasBall(competitor), competitor.team.id == game.away.team.id {
                Image(systemName: "football.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 56)
    }
}

/// A rounded card holding rows, like the iOS Sports groupings.
struct SportsCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(.headline).padding(.bottom, 4)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Darkened, not grey, so the backdrop's colour shows through as on iOS.
        .background(.black.opacity(0.38), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
    }
}

/// Coloured backdrop like the iOS app's team and league pages: the colour ripples slowly like a flag
/// in the wind (light and dark folds drifting across), then fades to black down the page.
/// Holds still with Reduce Motion.
struct Backdrop: View {
    let color: Color
    /// Home's flatter look: shallow folds and almost no fade, so the colour reads as one green like iOS's.
    var flat = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            // Double: as a Float, a date this large only moves in 64-second steps, so the folds froze then jumped.
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 4, height: 4, points: Self.points(t), colors: folds, smoothsColors: true)
        }
        // Lighter at the top than before, so the colour carries further down behind the cards.
        .overlay(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(flat ? 0 : 0.15), location: 0.5),
                                        .init(color: .black.opacity(flat ? 0.18 : 0.65), location: 1)],
                                startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()
    }

    /// Bands of highlight and shadow, diagonally offset row to row, read as cloth folds once the points move.
    /// They change brightness only, keeping hue and saturation, so the colour stays true (the Home green
    /// matches iOS's #2D6526 instead of greying out).
    private var folds: [Color] {
        let depth = flat ? 0.65 : 1.25 // how far folds swing from the base colour
        let light = color.brightness(1 + 0.18 * depth), lit = color.brightness(1 + 0.07 * depth)
        let dark = color.brightness(1 - 0.28 * depth), shade = color.brightness(1 - 0.14 * depth)
        return [lit, dark, light, shade,
                shade, light, dark, lit,
                light, color, shade, light,
                dark, lit, color, dark]
    }

    /// Inner and edge points ripple on slow, out-of-phase waves like a flag; corners stay pinned.
    static func points(_ t: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double, _ size: Float = 0.07) -> Float { size * Float(sin(t * speed + phase)) }
        let third: Float = 1 / 3, twoThirds: Float = 2 / 3
        return [
            [0, 0], [third + wave(0.8, 0), 0], [twoThirds + wave(0.7, 1), 0], [1, 0],
            [0, third + wave(0.9, 2)], [third + wave(1.1, 0.5, 0.09), third + wave(0.95, 1.5, 0.08)],
            [twoThirds + wave(1.0, 2.5, 0.09), third + wave(1.2, 0.2, 0.08)], [1, third + wave(0.85, 3)],
            [0, twoThirds + wave(0.75, 1.2)], [third + wave(1.15, 3.1, 0.09), twoThirds + wave(0.9, 0.7, 0.08)],
            [twoThirds + wave(0.95, 1.8, 0.09), twoThirds + wave(1.05, 2.9, 0.08)], [1, twoThirds + wave(0.8, 0.4)],
            [0, 1], [third + wave(0.7, 2.2), 1], [twoThirds + wave(0.9, 0.9), 1], [1, 1],
        ]
    }
}

extension View {
    /// Puts the waving backdrop behind a scrolling page and lets it run up under the toolbar,
    /// so the title bar blends in instead of sitting on its own band.
    func backdrop(_ color: Color, flat: Bool = false) -> some View {
        // Extended under the sidebar, so it floats as Liquid Glass over the colour instead of a flat strip.
        background { Backdrop(color: color, flat: flat).backgroundExtensionEffect() }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

extension Color {
    /// Same hue and saturation, brightness scaled (capped at full).
    func brightness(_ factor: Double) -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: saturation, brightness: min(1, brightness * factor), opacity: alpha)
    }

    /// The iOS Sports app's green, #2D6526, sampled from its home screen.
    static let sportsGreen = Color(red: 45 / 255, green: 101 / 255, blue: 38 / 255)
    /// Navy used behind league pages.
    static let sportsNavy = Color(red: 0.05, green: 0.12, blue: 0.27)
}
