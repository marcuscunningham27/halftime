import SportsKit
import SwiftUI

/// A question box on the game page, answered from that game's data by the engine chosen in Settings.
struct AskCard: View {
    let game: Game
    let detail: GameDetail

    @State private var question = ""
    @State private var asked: String?
    @State private var answer: String?
    @State private var error: String?
    @State private var isLoading = false
    @AppStorage(RecapEngine.storageKey) private var engine = RecapEngine.onDevice

    var body: some View {
        if engine.unavailableReason == nil, game.status != .scheduled {
            SportsCard(title: "Ask About the Game") {
                HStack(spacing: 8) {
                    TextField(Self.suggestions(for: game.leagueID).first ?? "Ask a question", text: $question)
                        .textFieldStyle(.plain)
                        .onSubmit { ask() }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Ask", systemImage: "arrow.up") { ask() }
                            .labelStyle(.iconOnly).buttonStyle(.glass)
                            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.vertical, 6)
                // Common questions for this sport, one click to ask.
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Self.suggestions(for: game.leagueID), id: \.self) { suggestion in
                            Button(suggestion) { ask(suggestion) }
                                .buttonStyle(.glass).controlSize(.small)
                                .disabled(isLoading)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                if let asked, let answer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asked).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(answer).textSelection(.enabled)
                        Label(engine.credit, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                } else if let error {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                }
            }
        }
    }

    /// Quick questions that suit the sport's stats.
    static func suggestions(for leagueID: League.ID) -> [String] {
        switch leagueID {
        case League.nfl.id: ["Who had the most yards?", "Who were the top passers?", "How did turnovers change the game?", "What were the key scoring drives?"]
        case League.nba.id: ["Who's the top scorer?", "How are the teams shooting from three?", "Who leads in rebounds and assists?", "What was the biggest run?"]
        case League.mlb.id: ["Who drove in the runs?", "How did the starting pitchers do?", "Who had the big hits?", "Which inning decided it?"]
        case League.nhl.id: ["Who scored the goals?", "How did the goalies play?", "How did the power plays go?", "Which team controlled the shots?"]
        case League.epl.id: ["Who scored and when?", "Which team had more of the ball?", "Who were the standout players?", "What were the big chances?"]
        case League.afl.id: ["Who kicked the most goals?", "Who had the most disposals?", "Which quarter swung it?", "Who won the clearances?"]
        case League.nrl.id: ["Who scored the tries?", "Which team won the territory battle?", "What were the turning points?", "Who were the best players?"]
        default: ["Who were the best players?", "What were the turning points?"]
        }
    }

    private func ask(_ suggestion: String? = nil) {
        let text = (suggestion ?? question).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }
        isLoading = true
        Task {
            do {
                answer = try await engine.answer(text, game: game, detail: detail)
                asked = text
                if suggestion == nil { question = "" }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
