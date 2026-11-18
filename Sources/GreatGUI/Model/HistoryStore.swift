import Foundation

/// One finished run. The run line never holds a secret: secrets travel in the environment.
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var run: String
    var cwd: String?
    var mode: String        // "run" or "tty" from the window, "cli" from a terminal, "sched" from launchd, "exec" for great-gui exec
    var code: Int32
    var seconds: Double
    var startedAt: Date
}

/// Newest first, at most `limit` entries, in one JSON file under Application Support.
struct HistoryStore {
    let url: URL
    let limit: Int

    /// `GREAT_GUI_HISTORY` points the file elsewhere (a test instance keeps its runs out of yours).
    init(url: URL? = nil, limit: Int = 500) {
        self.limit = limit
        if let url {
            self.url = url
        } else if let p = ProcessInfo.processInfo.environment["GREAT_GUI_HISTORY"], !p.isEmpty {
            self.url = URL(fileURLWithPath: NSString(string: p).expandingTildeInPath)
        } else {
            self.url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("the-great-gui/history.json")
        }
    }

    func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    /// Loads, inserts newest first, saves, and returns the list: the window and the command line both go through
    /// it, so a scheduled run landing while the window is open is not lost on the window's next save.
    @discardableResult
    func append(_ entry: HistoryEntry) -> [HistoryEntry] {
        var all = load()
        all.insert(entry, at: 0)
        save(all)
        return Array(all.prefix(limit))
    }

    /// The mode as a word.
    static func modeName(_ mode: String) -> String {
        switch mode {
        case "tty": "terminal"
        case "sched": "scheduled"
        case "cli": "shell"
        default: "run"
        }
    }

    func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Array(entries.prefix(limit))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
