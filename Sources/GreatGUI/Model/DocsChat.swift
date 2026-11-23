import Foundation
import Observation
import Runner

@MainActor @Observable
final class DocsChat {
    enum Provider: String, CaseIterable, Identifiable, Sendable {
        case codex, cortex
        var id: Self { self }
        var title: String { self == .codex ? "Codex" : "Cortex" }
    }

    struct Source: Decodable, Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let path: String
    }

    struct Message: Identifiable, Sendable {
        let id = UUID()
        let provider: Provider
        let role: String
        let text: String
        var sources: [Source] = []
    }

    struct Reply: Decodable, Sendable {
        var answer: String?
        var sources: [Source]?
        var error: String?
    }

    private struct Request: Encodable {
        struct Turn: Encodable {
            let role: String
            let text: String
        }
        let question: String
        let history: [Turn]
        let currentSource: String?
    }

    var provider: Provider = .codex
    var draft = ""
    private(set) var messages: [Message] = []
    private(set) var asking = false
    private(set) var note: AppModel.Note?

    private let run: @Sendable (Provider, Data) throws -> Reply

    init(run: @escaping @Sendable (Provider, Data) throws -> Reply = { try DocsChat.request($0, $1) }) {
        self.run = run
    }

    func submit(currentSource: String? = nil) {
        let question = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !asking, !question.isEmpty else { return }
        let picked = provider
        let history = messages.filter { $0.provider == picked }.suffix(6).map {
            Request.Turn(role: $0.role, text: String($0.text.prefix(3000)))
        }
        let request = Request(question: question, history: history, currentSource: currentSource)
        asking = true
        note = nil
        draft = ""
        messages.append(.init(provider: picked, role: "user", text: question))
        let invoke = run
        Task {
            defer { asking = false }
            do {
                let data = try JSONEncoder().encode(request)
                let result = try await Task.detached(priority: .userInitiated) { try invoke(picked, data) }.value
                guard let answer = result.answer, !answer.isEmpty else {
                    throw DocsBuild.Failure(message: result.error ?? "The provider returned no answer.")
                }
                messages.append(.init(provider: picked, role: "assistant", text: answer, sources: result.sources ?? []))
            } catch {
                messages.removeLast()
                note = .init(ok: false, text: "\(picked.title) could not answer", fix: error.localizedDescription)
                draft = question
            }
        }
    }

    func reset() {
        guard !asking else { return }
        messages.removeAll()
        draft = ""
        note = nil
    }

    nonisolated private static func request(_ provider: Provider, _ body: Data) throws -> Reply {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessRun.defaultShell())
        process.arguments = ["-lc", "exec ds-next ask-canon --provider " + provider.rawValue]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.environment = DocsBuild.toolEnvironment().filter { !$0.key.hasPrefix("GREAT_GUI_") }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        try input.fileHandleForWriting.write(contentsOf: body)
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw DocsBuild.Failure(message: "Install a version of ds-next with the ask-canon command and try again.")
        }
        return reply
    }
}
