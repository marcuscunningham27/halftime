import SportsKit
import SwiftUI

/// Questions about the game. The one-click questions are answered straight from the stats where they can be;
/// typed questions, and the few quick ones that need judgement, go to the engine chosen in Settings.
struct AskCard: View {
    let game: Game
    let detail: GameDetail

    @State private var question = ""
    @State private var asked: String?
    @State private var answer: String?
    /// Whether `answer` came from the stats rather than the model, for the credit line.
    @State private var fromStats = false
    @State private var error: String?
    @State private var isLoading = false
    @AppStorage(RecapEngine.storageKey) private var engine = RecapEngine.onDevice

    private var questions: [QuickQuestion] { QuickQuestion.list(for: game.leagueID) }
    private var canAskModel: Bool { engine.unavailableReason == nil }

    var body: some View {
        if game.status != .scheduled {
            SportsCard(title: "Ask About the Game") {
                // Free-form questions need the model, so the box only shows when it can run.
                if canAskModel {
                    HStack(spacing: 8) {
                        TextField(questions.first?.text ?? "Ask a question", text: $question)
                            .textFieldStyle(.plain)
                            .onSubmit { ask(question) }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Ask", systemImage: "arrow.up") { ask(question) }
                                .labelStyle(.iconOnly).buttonStyle(.glass)
                                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.top, 6)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(questions) { quick in
                            Button(quick.text) { ask(quick.text, quick: quick) }
                                .buttonStyle(.glass).controlSize(.small)
                                .disabled(isLoading)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                if let asked, let answer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asked).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(answer).lineSpacing(3).textSelection(.enabled)
                        Label(fromStats ? "From ESPN game stats" : engine.credit, systemImage: fromStats ? "chart.bar" : "sparkles")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                    }
                    .padding(.bottom, 4)
                } else if let error {
                    Text(error).font(.subheadline).foregroundStyle(.red).padding(.bottom, 4)
                }
            }
        }
    }

    /// Stats first (quick questions, and typed ones naming a stat leader); the model for the rest, when it can run.
    private func ask(_ text: String, quick: QuickQuestion? = nil) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }
        let stats = quick.map { GameFacts.answer($0, game: game, detail: detail) }
            ?? GameFacts.answer(typed: text, game: game, detail: detail)
        if let stats {
            (asked, answer, fromStats, error) = (text, stats, true, nil)
            if quick == nil { question = "" }
            return
        }
        guard canAskModel else {
            (asked, answer, error) = (nil, nil, "This one needs AI. Turn on Apple Intelligence or add a Claude key in Settings › Summaries.")
            return
        }
        isLoading = true
        Task {
            do {
                answer = try await engine.answer(text, game: game, detail: detail)
                asked = text
                fromStats = false
                if quick == nil { question = "" }
                error = nil
            } catch {
                // Clear the previous answer, or it hides this error.
                (asked, answer) = (nil, nil)
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
