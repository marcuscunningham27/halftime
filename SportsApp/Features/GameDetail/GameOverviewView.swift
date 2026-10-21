import MapKit
import SportsKit
import SwiftUI

/// Where and when, what's on TV, weather at kickoff, the betting line, standings and win chance.
struct GameOverviewView: View {
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.regionDefault
    let game: Game
    let overview: GameOverview

    @State private var venueTimeZone: TimeZone?
    @State private var weather: Weather?

    var body: some View {
        VStack(spacing: 12) {
            if let venue = overview.venue {
                venueBanner(venue)
            }
            gameInfo
            if let weather {
                weatherCard(weather)
            }
            if let odds = overview.odds {
                oddsCard(odds)
            }
            standingsCard
            if game.status != .final, !overview.winProbability.isEmpty {
                winProbabilityCard
            }
        }
        // Geocode the venue once for its time zone and coordinates, then fetch weather for kickoff.
        .task(id: overview.venue?.place) {
            guard let venue = overview.venue else { return }
            // City level: Apple's geocoder rejects many stadium names, and the city is enough for weather and time zone.
            let address = [venue.place ?? venue.name, venue.country].compactMap { $0 }.joined(separator: ", ")
            guard let request = MKGeocodingRequest(addressString: address),
                  let item = try? await request.mapItems.first else { return }
            venueTimeZone = item.timeZone
            let coordinate = item.location.coordinate
            weather = try? await OpenMeteo.weather(latitude: coordinate.latitude, longitude: coordinate.longitude, at: game.startDate)
        }
    }

    private func venueBanner(_ venue: GameOverview.Venue) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: venue.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.white.opacity(0.08))
            }
            .frame(height: 180)
            .clipped()
            // A filled image still takes clicks outside its clipped frame, which blocked the tab picker above.
            .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name).font(.title3.weight(.bold))
                if let place = venue.place { Text(place).font(.subheadline).foregroundStyle(.secondary) }
            }
            .padding(14)
        }
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private var gameInfo: some View {
        SportsCard(title: "Game Info") {
            InfoRow(symbol: "calendar", title: "Your time",
                    value: game.startDate.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
            if let zone = venueTimeZone, zone.secondsFromGMT(for: game.startDate) != TimeZone.current.secondsFromGMT(for: game.startDate) {
                var style = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
                let _ = style.timeZone = zone
                InfoRow(symbol: "clock", title: "Local time\(overview.venue?.city.map { " in \($0)" } ?? "")",
                        value: game.startDate.formatted(style))
            }
            if let venue = overview.venue {
                InfoRow(symbol: "mappin.and.ellipse", title: "Venue", value: [venue.name, venue.place].compactMap { $0 }.joined(separator: ", "))
            }
            if !overview.broadcasts.isEmpty {
                InfoRow(symbol: "tv", title: "Watch", value: overview.broadcasts.joined(separator: ", "))
            }
            if let note = game.note {
                InfoRow(symbol: "trophy", title: "Event", value: note)
            }
            if let series = game.seriesSummary {
                InfoRow(symbol: "rectangle.stack", title: "Series", value: series)
            }
            if let attendance = overview.attendance {
                InfoRow(symbol: "person.3", title: "Attendance", value: attendance.formatted())
            }
        }
    }

    private func weatherCard(_ weather: Weather) -> some View {
        SportsCard(title: game.status == .scheduled ? "Weather at Kickoff" : "Weather at the Start") {
            HStack(spacing: 14) {
                Image(systemName: Self.symbol(for: weather.code))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(units.temperature(weather.temperature))
                        .font(.score(34))
                    Text(weather.summary).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let wind = weather.windSpeed {
                        Label(units.speed(wind), systemImage: "wind")
                    }
                    if let rain = weather.precipitationChance {
                        Label("\(rain)%", systemImage: "drop")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            Text("Forecast by Open-Meteo for the venue's location.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func oddsCard(_ odds: GameOverview.Odds) -> some View {
        SportsCard(title: "Odds") {
            if let spread = odds.homeSpread {
                // A positive home line means the away team is favoured by that much.
                let favourite = spread > 0 ? game.away.team : game.home.team
                InfoRow(symbol: "plusminus", title: "Spread",
                        value: spread == 0 ? "Pick'em" : "\(favourite.abbreviation) −\(abs(spread).formatted(.number.precision(.fractionLength(0...1))))")
            }
            if let total = odds.overUnder {
                InfoRow(symbol: "sum", title: "Over/Under", value: total.formatted(.number.precision(.fractionLength(0...1))))
            }
            if let away = odds.awayMoneyLine, let home = odds.homeMoneyLine {
                InfoRow(symbol: "dollarsign.circle", title: "Moneyline",
                        value: "\(game.away.team.abbreviation) \(Self.signed(away)) · \(game.home.team.abbreviation) \(Self.signed(home))")
            }
            Text("Average of \(odds.books.count) sportsbook\(odds.books.count == 1 ? "" : "s"): \(odds.books.joined(separator: ", ")).")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
        }
    }

    @ViewBuilder
    private var standingsCard: some View {
        let lines = [game.away, game.home].compactMap { competitor in
            overview.standings.first { $0.teamID == competitor.team.id }.map { (competitor.team, $0) }
        }
        if !lines.isEmpty {
            SportsCard(title: "Standings") {
                ForEach(lines, id: \.0.id) { team, standing in
                    HStack(spacing: 10) {
                        TeamLogo(team: team, size: 24)
                        Text(team.shortName).font(.headline)
                        Spacer()
                        Text("\(Game.ordinal(standing.position)) in \(standing.group)")
                        if let record = standing.record {
                            Text(record).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var winProbabilityCard: some View {
        let away = overview.winProbability[game.away.team.id] ?? 0
        let home = overview.winProbability[game.home.team.id] ?? 0
        let total = max(away + home, 1)
        return SportsCard(title: "Win Probability") {
            HStack {
                Text("\(game.away.team.abbreviation) \(away.formatted(.number.precision(.fractionLength(1))))%")
                Spacer()
                Text("\(home.formatted(.number.precision(.fractionLength(1))))% \(game.home.team.abbreviation)")
            }
            .font(.headline)
            .monospacedDigit()
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    Capsule().fill(game.away.team.color).frame(width: (geometry.size.width - 4) * away / total)
                    Capsule().fill(game.home.team.color)
                }
            }
            .frame(height: 8)
            .padding(.vertical, 6)
            Text("ESPN Matchup Predictor, before the game.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "−\(abs(value))"
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.sun.fill"
        }
    }
}

/// Icon, label, value: one fact in an overview card.
struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
