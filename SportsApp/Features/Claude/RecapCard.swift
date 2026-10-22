import SportsKit
import SwiftUI

/// The story of a game: ESPN's written recap once a finished game has one, otherwise a summary built from
/// the stats (which follows a live game as it updates). Either can be rewritten by the engine chosen in
/// Settings, when it's available.
struct RecapCard: View {
    let game: Game
    let detail: GameDetail

    @State private var written: String?
    @State private var error: String?
    @State private var isLoading = false
    @State private var showsFullStory = false
    @AppStorage(RecapEngine.storageKey) private var engine = RecapEngine.onDevice

    var body: some View {
        if game.status != .scheduled {
            SportsCard(title: isLive ? "Catch Me Up" : "Recap") {
                VStack(alignment: .leading, spacing: 8) {
                    if let written {
                        Text(written).lineSpacing(3).textSelection(.enabled)
                        footer(Label(engine.credit, systemImage: "sparkles"))
                    } else if !isLive, let story = detail.overview.recap {
                        Text(story.headline).font(.headline)
                        ForEach(Array(story.paragraphs.prefix(showsFullStory ? .max : 2).enumerated()), id: \.offset) {
                            Text($0.element).lineSpacing(3).textSelection(.enabled)
                        }
                        footer(HStack(spacing: 12) {
                            Label("Story from ESPN", systemImage: "newspaper")
                            if story.paragraphs.count > 2 {
                                Button(showsFullStory ? "Show less" : "Read more") { showsFullStory.toggle() }
                                    .buttonStyle(.link)
                            }
                            if let url = story.url { Link("Open on ESPN", destination: url) }
                        })
                    } else {
                        // Rebuilt from the latest stats on every refresh of the game.
                        Text(GameFacts.summary(game: game, detail: detail)).lineSpacing(3).textSelection(.enabled)
                        footer(Label("From ESPN game stats", systemImage: "chart.bar"))
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var isLive: Bool { game.status == .live }

    /// Credit on the left; on the right, a button to have the AI write (or rewrite) it, when the engine can run.
    private func footer(_ credit: some View) -> some View {
        HStack {
            credit.font(.caption).foregroundStyle(.secondary)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else if engine.unavailableReason == nil {
                Button(written == nil ? "Summarise with \(engine == .claude ? "Claude" : "AI")" : "Rewrite",
                       systemImage: written == nil ? "sparkles" : "arrow.clockwise") { summarise() }
                    .buttonStyle(.glass).controlSize(.small)
                    .help(written == nil ? "Have \(engine.title) write it up instead" : "Write it again with the latest plays")
            }
        }
    }

    private func summarise() {
        isLoading = true
        Task {
            do {
                written = try await engine.recap(game: game, detail: detail)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
