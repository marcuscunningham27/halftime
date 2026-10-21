import SportsKit
import SwiftUI

/// A recap of a finished game, or the story so far of a live one, on request, from the engine chosen
/// in Settings. Hidden when that engine can't run (no API key, or no Apple Intelligence).
struct RecapCard: View {
    let game: Game
    let detail: GameDetail

    @State private var recap: String?
    @State private var error: String?
    @State private var isLoading = false
    @AppStorage(RecapEngine.storageKey) private var engine = RecapEngine.onDevice

    var body: some View {
        if engine.unavailableReason == nil, game.status != .scheduled {
            SportsCard(title: isLive ? "Catch Me Up" : "Recap") {
                if let recap {
                    Text(recap).font(.body).lineSpacing(3).textSelection(.enabled).padding(.vertical, 6)
                    HStack {
                        Label(engine.credit, systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise") { summarise() }
                            .labelStyle(.iconOnly).buttonStyle(.glass).disabled(isLoading)
                            .help("Write the recap again with the latest plays")
                    }
                } else {
                    HStack {
                        Text(error ?? (isLive ? "Just tuned in? What’s happened so far and what to watch for" : "A short summary of the game")
                             + ", written by \(engine == .claude ? "Claude" : "the on-device model").")
                            .font(.subheadline).foregroundStyle(error == nil ? .secondary : Color.red)
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(isLive ? "Catch Me Up" : "Summarise", systemImage: "sparkles") { summarise() }
                                .buttonStyle(.glass)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var isLive: Bool { game.status == .live }

    private func summarise() {
        isLoading = true
        Task {
            do {
                recap = try await engine.recap(game: game, detail: detail)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
