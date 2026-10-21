import AppIntents
import ImageIO
import SportsKit
import SwiftUI
import WidgetKit

@main
struct SportsWidgets: WidgetBundle {
    var body: some Widget {
        MyTeamsWidget()
        LeagueWidget()
    }
}

// MARK: - My Teams

/// Mirrors the iOS "My Teams" widget: each followed team's live, next or last game.
struct MyTeamsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyTeams", provider: MyTeamsProvider()) { entry in
            GamesWidgetView(entry: entry, title: "My Teams", symbol: "star.fill")
                .widgetURL(.openApp)
                .containerBackground(for: .widget) { WidgetBackground(color: .widgetGreen) }
        }
        .configurationDisplayName("My Teams")
        .description("Get quick access to live scores and fixtures for teams you follow.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MyTeamsProvider: TimelineProvider {
    func placeholder(in context: Context) -> GamesEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (GamesEntry) -> Void) {
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<GamesEntry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(entry.nextRefresh)))
        }
    }

    private func load() async -> GamesEntry {
        let teams = WidgetTeam.load()
        let leagues = WidgetTeam.loadLeagues().compactMap(League.with)
        guard !teams.isEmpty || !leagues.isEmpty else { return GamesEntry(message: "Follow a team in Halftime") }
        let provider = ESPNProvider()
        // Each followed team's live, next or last game, fetched in parallel, in follow order.
        let found = await withTaskGroup(of: (Int, Game?).self) { group in
            for (index, team) in teams.enumerated() {
                group.addTask { (index, try? await provider.featuredGame(for: team.ref)) }
            }
            var results: [(Int, Game?)] = []
            for await result in group { results.append(result) }
            return results
        }
        var games = found.sorted { $0.0 < $1.0 }.compactMap(\.1)
        // Spare rows go to followed leagues: today's games, else their latest results.
        for league in leagues where games.count < 6 {
            var more = (try? await provider.scoreboard(league: league, date: .now)) ?? []
            if more.isEmpty { more = (try? await provider.recentResults(league: league, before: .now)) ?? [] }
            games += more
        }
        var seen = Set<Game.ID>()
        let unique = games.filter { seen.insert($0.id).inserted }
        // Live, then results, then upcoming; within each, teams ahead of league fill-ins.
        let rank: (Game) -> Int = { [.live: 0, .final: 1, .scheduled: 2][$0.status] ?? 2 }
        let sorted = unique.enumerated().sorted { a, b in
            let x = rank(a.element), y = rank(b.element)
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
        return await GamesEntry(games: Array(sorted.prefix(6)), followed: Set(teams.map(\.ref)))
    }
}

// MARK: - League

enum LeagueOption: String, AppEnum {
    case nfl, nba, mlb, nhl, epl, afl, nrl

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "League"
    static let caseDisplayRepresentations: [LeagueOption: DisplayRepresentation] = [
        .nfl: "NFL", .nba: "NBA", .mlb: "MLB", .nhl: "NHL", .epl: "Premier League", .afl: "AFL", .nrl: "NRL",
    ]

    var league: League { League.with(id: rawValue) ?? .nfl }
}

struct SelectLeagueIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose League"
    static let description = IntentDescription("Show a league's next games.")

    @Parameter(title: "League", default: .nfl) var league: LeagueOption
}

/// Mirrors the iOS league widget: the league's games today, or its next day with games.
struct LeagueWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "League", intent: SelectLeagueIntent.self, provider: LeagueProvider()) { entry in
            GamesWidgetView(entry: entry, title: entry.title ?? "", league: entry.league)
                .widgetURL(.openApp)
                .containerBackground(for: .widget) { WidgetBackground(color: .widgetBlue) }
        }
        .configurationDisplayName("League")
        .description("Live scores and upcoming games for a league.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LeagueProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GamesEntry { .empty }

    func snapshot(for configuration: SelectLeagueIntent, in context: Context) async -> GamesEntry {
        await load(configuration.league.league)
    }

    func timeline(for configuration: SelectLeagueIntent, in context: Context) async -> Timeline<GamesEntry> {
        let entry = await load(configuration.league.league)
        return Timeline(entries: [entry], policy: .after(entry.nextRefresh))
    }

    private func load(_ league: League) async -> GamesEntry {
        let provider = ESPNProvider()
        // What's on: today's games, or if nothing is still to play today, the next day within a week that has games.
        var current = (try? await provider.scoreboard(league: league, date: .now)) ?? []
        var title = "Today"
        if !current.contains(where: { $0.status != .final }) {
            for offset in 1..<7 {
                let day = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
                let games = (try? await provider.scoreboard(league: league, date: day)) ?? []
                if !games.isEmpty {
                    current += games
                    title = day.formatted(.dateTime.weekday(.wide))
                    break
                }
            }
        }
        // Then the latest results, so the widget always shows how recent games finished.
        let recent = (try? await provider.recentResults(league: league, before: .now)) ?? []
        var seen = Set<Game.ID>()
        let live = current.filter { $0.status == .live }
        let upcoming = current.filter { $0.status == .scheduled }.sorted { $0.startDate < $1.startDate }
        let finals = (current + recent).filter { $0.status == .final }.sorted { $0.startDate > $1.startDate }
        let games = (live + upcoming + finals).filter { seen.insert($0.id).inserted }
        guard !games.isEmpty else {
            return GamesEntry(message: "No recent \(league.abbreviation) games", title: "", league: league)
        }
        if live.isEmpty, upcoming.isEmpty { title = "Recent" }
        return await GamesEntry(games: Array(games.prefix(6)), followed: Set(WidgetTeam.load().map(\.ref)),
                                title: title, league: league)
    }
}

// MARK: - Entry

struct GamesEntry: TimelineEntry {
    var date = Date.now
    var games: [Game] = []
    /// Widgets can't load images asynchronously, so logos come with the timeline.
    var logos: [URL: NSImage] = [:]
    var followed: Set<Follows.TeamRef> = []
    var message: String?
    var title: String?
    var league: League?

    static let empty = GamesEntry()

    init(message: String? = nil, title: String? = nil, league: League? = nil) {
        self.message = message
        self.title = title
        self.league = league
    }

    init(games: [Game], followed: Set<Follows.TeamRef>, title: String? = nil, league: League? = nil) async {
        self.games = games
        self.followed = followed
        self.title = title
        self.league = league
        let urls = Set(games.flatMap { [$0.away.team.logoURL, $0.home.team.logoURL] }.compactMap { $0 })
            .union([league.flatMap(\.logoURL)].compactMap { $0 })
        logos = await withTaskGroup(of: (URL, NSImage?).self) { group in
            for url in urls {
                group.addTask {
                    let data = try? await URLSession.shared.data(from: url).0
                    return (url, data.flatMap(Self.thumbnail))
                }
            }
            var images: [URL: NSImage] = [:]
            for await (url, image) in group { images[url] = image }
            return images
        }
    }

    /// ESPN logos are 500×500; a dozen at that size overflow the widget's snapshot archive and it renders blank.
    nonisolated static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 48, height: 48))
    }

    /// Live: as often as WidgetKit allows. Upcoming: wake for the first start. Otherwise hourly.
    var nextRefresh: Date {
        if games.contains(where: { $0.status == .live }) { return .now.addingTimeInterval(5 * 60) }
        let hour = Date.now.addingTimeInterval(3600)
        return games.filter { $0.status == .scheduled }.map(\.startDate).filter { $0 > .now }.min().map { min($0, hour) } ?? hour
    }
}

extension League {
    var logoURL: URL? {
        URL(string: id == League.epl.id
            ? "https://a.espncdn.com/i/leaguelogos/soccer/500/23.png"
            : "https://a.espncdn.com/i/teamlogos/leagues/500/\(id).png")
    }
}

// MARK: - Views

extension URL {
    /// Handled by the app's main window scene, so a tap opens the window even when it was closed.
    static let openApp = URL(string: "sportsapp://open")!
}

extension Color {
    static let widgetGreen = Color(red: 0.10, green: 0.42, blue: 0.20)
    static let widgetBlue = Color(red: 0.22, green: 0.33, blue: 0.58)
}

struct WidgetBackground: View {
    let color: Color

    var body: some View {
        LinearGradient(colors: [color, color.mix(with: .black, by: 0.35)], startPoint: .top, endPoint: .bottom)
    }
}

/// Header plus one, two or three columns of compact score rows, sized to the widget family.
struct GamesWidgetView: View {
    let entry: GamesEntry
    let title: String
    var symbol: String?
    var league: League?

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            header
            if entry.games.isEmpty {
                Spacer()
                Text(entry.message ?? "No games")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                grid
                Spacer(minLength: 0)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let league {
                WidgetLogo(image: league.logoURL.flatMap { entry.logos[$0] }, size: 16)
                if family != .systemSmall {
                    Text(league.abbreviation).font(.headline)
                }
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            } else if let symbol {
                Image(systemName: symbol).font(.headline)
                if family != .systemSmall {
                    Text(title).font(.headline)
                }
            }
            Spacer()
            Image(systemName: "sportscourt").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var grid: some View {
        switch family {
        case .systemSmall:
            stack(Array(entry.games.prefix(3)), large: false)
        case .systemMedium:
            columns(entry.games.prefix(6), large: false)
        default:
            if league != nil {
                // The iOS league widget's large size: one column of big rows, then "No Other Events".
                VStack(spacing: 0) {
                    ForEach(Array(entry.games.prefix(4).enumerated()), id: \.element.id) { index, game in
                        if index > 0 { Divider() }
                        bigRow(game).padding(.vertical, 8)
                    }
                    if entry.games.count < 4 {
                        Divider()
                        Text("No Other Events").font(.subheadline).foregroundStyle(.secondary).padding(.top, 10)
                    }
                }
            } else {
                columns(entry.games.prefix(6), large: true)
            }
        }
    }

    /// Rows separated by hairlines, like iOS.
    private func stack(_ games: [Game], large: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                if index > 0 { Divider().opacity(0.6) }
                row(game, large: large).padding(.vertical, large ? 7 : 4)
            }
        }
    }

    private func columns(_ games: ArraySlice<Game>, large: Bool) -> some View {
        let list = Array(games)
        let left = Array(list.prefix(3)), right = Array(list.dropFirst(3))
        return HStack(alignment: .top, spacing: 10) {
            stack(left, large: large)
            if !right.isEmpty {
                Divider().opacity(0.6)
                stack(right, large: large)
            }
        }
    }

    /// Large league row: big logos with abbreviations, records (or scores) beside them, big time in the middle.
    private func bigRow(_ game: Game) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 3) {
                WidgetLogo(image: game.away.team.logoURL.flatMap { entry.logos[$0] }, size: 32)
                Text(game.away.team.abbreviation).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 44)
            score(game, game.away, large: true)
            VStack(spacing: 1) {
                status(game).font(.headline)
                if let second = secondLine(game) {
                    Text(second).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            score(game, game.home, large: true)
            VStack(spacing: 3) {
                WidgetLogo(image: game.home.team.logoURL.flatMap { entry.logos[$0] }, size: 32)
                Text(game.home.team.abbreviation).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.away.team.shortName) at \(game.home.team.shortName), \(game.statusDetail)")
    }

    /// Logo, score, status, score, logo; the large size adds the league and team abbreviations.
    private func row(_ game: Game, large: Bool) -> some View {
        VStack(spacing: 2) {
            if large, league == nil {
                Text(game.league.abbreviation).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                side(game, game.away, large: large, starFirst: true)
                score(game, game.away, large: large)
                VStack(spacing: 0) {
                    status(game).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    if let second = secondLine(game) {
                        Text(second).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                score(game, game.home, large: large)
                side(game, game.home, large: large, starFirst: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.away.team.shortName) \(game.away.score ?? 0), \(game.home.team.shortName) \(game.home.score ?? 0), \(game.statusDetail)")
    }

    private func side(_ game: Game, _ competitor: Game.Competitor, large: Bool, starFirst: Bool) -> some View {
        let star = entry.followed.contains(.init(leagueID: game.leagueID, teamID: competitor.team.id))
        let logo: CGFloat = large ? 24 : 18
        // Fixed width (star included), so the middle column lines up from row to row.
        return HStack(spacing: 1) {
            Image(systemName: "star.fill").font(.system(size: 6)).opacity(star && starFirst ? 1 : 0)
            VStack(spacing: 1) {
                WidgetLogo(image: competitor.team.logoURL.flatMap { entry.logos[$0] }, size: logo)
                if large {
                    Text(competitor.team.abbreviation).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: large ? 30 : logo)
            Image(systemName: "star.fill").font(.system(size: 6)).opacity(star && !starFirst ? 1 : 0)
        }
    }

    /// Score once it's started; before then the team's record in small type, as iOS does.
    /// Fixed width, hugging its logo (leading for away, trailing for home), so scores and records
    /// of different lengths don't push the middle around.
    private func score(_ game: Game, _ competitor: Game.Competitor, large: Bool) -> some View {
        let away = competitor.team.id == game.away.team.id
        return Group {
            if let score = competitor.score {
                Text(score, format: .number)
                    .font(.custom("ChakraPetch-Bold", size: large ? 22 : 18)) // bundled, as in the app
                    .monospacedDigit()
                    // Basketball's three-digit scores shrink a little rather than truncate.
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(game.isLosing(competitor) ? .secondary : .primary)
            } else if family == .systemLarge, let record = competitor.record {
                Text(record).font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // Medium columns are narrow, so scores get less room there and records are left out (as on iOS).
        .frame(width: family == .systemLarge ? 46 : 32, alignment: away ? .leading : .trailing)
    }

    @ViewBuilder
    private func status(_ game: Game) -> some View {
        switch game.status {
        case .live:
            Text(game.compactPeriod).foregroundStyle(.red)
        case .scheduled:
            Text(game.startDate, format: .dateTime.hour().minute())
        case .final:
            Text(game.statusDetail)
        }
    }

        /// Under the status: the date for every result ("19/10"), the weekday for fixtures that aren't today.
    private func secondLine(_ game: Game) -> String? {
        switch game.status {
        case .live: nil
        case .final: game.startDate.formatted(.dateTime.day().month(.twoDigits))
        case .scheduled:
            Calendar.current.isDateInToday(game.startDate) ? nil : game.startDate.formatted(.dateTime.weekday(.abbreviated))
        }
    }
}

/// Team or league logo. When macOS fades desktop widgets (vibrant mode), logos keep their detail
/// as greyscale instead of flattening into solid shapes.
struct WidgetLogo: View {
    let image: NSImage?
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if let image {
                if renderingMode == .vibrant {
                    Image(nsImage: image).resizable().scaledToFit().grayscale(1).luminanceToAlpha()
                } else {
                    Image(nsImage: image).resizable().widgetAccentedRenderingMode(.desaturated).scaledToFit()
                }
            } else {
                Circle().fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
    }
}

private extension Game {
    func isLosing(_ competitor: Competitor) -> Bool {
        guard status == .final, let score = competitor.score else { return false }
        let other = competitor.team.id == home.team.id ? away : home
        return score < (other.score ?? 0)
    }
}
