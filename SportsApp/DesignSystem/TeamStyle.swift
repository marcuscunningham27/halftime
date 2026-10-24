import SportsKit
import SwiftUI

extension League {
    var symbolName: String {
        switch id {
        case League.nfl.id, League.cfb.id: "football"
        case League.nba.id, League.wnba.id: "basketball"
        case League.mlb.id: "baseball"
        case League.nhl.id: "hockey.puck"
        case League.epl.id, League.ucl.id, League.mls.id: "soccerball"
        default: "sportscourt"
        }
    }
}


struct LeagueLogo: View {
    let league: League
    var size: CGFloat = 20

    var body: some View {
        AsyncImage(url: league.logoURL) { image in
            // A thin white halo keeps dark logos (the Premier League's) visible on dark backgrounds.
            image.resizable().scaledToFit()
                .shadow(color: .white.opacity(0.9), radius: 0.6)
                .shadow(color: .white.opacity(0.5), radius: 1.2)
        } placeholder: {
            Image(systemName: league.symbolName)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Team {
    var color: Color {
        guard let hex = colorHex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return .secondary }
        return Color(red: Double(value >> 16 & 0xFF) / 255,
                     green: Double(value >> 8 & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Start time, final text, or a LIVE pill over the clock, so "live" isn't carried by colour alone.
struct GameStatus: View {
    let game: Game
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        switch game.status {
        case .scheduled:
            Text(game.startDate, format: .dateTime.hour().minute())
        case .final:
            Text(game.statusDetail).foregroundStyle(.secondary)
        case .live:
            VStack(alignment: alignment, spacing: 3) {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.red, in: .capsule)
                Text(game.statusDetail).foregroundStyle(.red)
            }
        }
    }
}

struct TeamLogo: View {
    let team: Team
    var size: CGFloat = 24

    var body: some View {
        AsyncImage(url: team.logoURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Circle().fill(team.color.opacity(0.3))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Game {
    func isLosing(_ competitor: Competitor) -> Bool {
        guard status == .final, let score = competitor.score else { return false }
        let other = competitor.team.id == home.team.id ? away : home
        return score < (other.score ?? 0)
    }


    /// What VoiceOver says for a game, e.g. "Commanders 17, 49ers 23, live, 4:11 - 4th".
    var accessibilitySummary: String {
        let teams = status == .scheduled
            ? "\(away.team.displayName) at \(home.team.displayName)"
            : "\(away.team.shortName) \(away.score ?? 0), \(home.team.shortName) \(home.score ?? 0)"
        let when = switch status {
        case .scheduled: "starts \(startDate.formatted(date: .abbreviated, time: .shortened))"
        case .live: "live, \(statusDetail)"
        case .final: statusDetail
        }
        return "\(teams), \(when)"
    }

    /// Menu bar text, e.g. "WSH 3 – 13 SF · Q2".
    var compactScore: String {
        "\(away.team.abbreviation) \(away.score ?? 0) – \(home.score ?? 0) \(home.team.abbreviation) · \(compactPeriod)"
    }
}
