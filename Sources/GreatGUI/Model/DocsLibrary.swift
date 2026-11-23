import AppKit
import Darwin
import Foundation
import Observation
import Registry
import Runner

/// The local canon and team skills site. The last good build remains available while a new one runs.
@MainActor @Observable
final class DocsLibrary {
    private(set) var building = false
    private(set) var opening = false
    private(set) var builtAt: Date?
    private(set) var url: URL?
    private(set) var revision = 0
    private(set) var note: AppModel.Note?
    let chat = DocsChat()
    var showingChat = true
    private(set) var navigationRevision = 0
    private(set) var currentSource: String?
    private var displayedURL: URL?
    private var sourcePath: String?

    var pageURL: URL? {
        guard let url else { return nil }
        return sourcePath.map { url.appending(path: $0) } ?? url
    }

    private let site: URL
    private let cache: URL
    private let rebuild: @Sendable (URL) throws -> Void
    private let openURL: (URL) -> Bool
    private var server: DocsServer?

    init(cache: URL = DocsBuild.cacheDirectory(),
         rebuild: @escaping @Sendable (URL) throws -> Void = { try DocsBuild.rebuild(in: $0) },
         openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.cache = cache
        site = cache.appendingPathComponent("site", isDirectory: true)
        self.rebuild = rebuild
        self.openURL = openURL
        builtAt = Self.buildDate(site)
    }

    func openCanon() {
        guard !opening else { return }
        if builtAt == nil {
            build(openAfter: true)
            return
        }
        guard url == nil else { return }
        opening = true
        Task {
            defer { opening = false }
            do {
                let listener = try DocsServer(site: site)
                url = try await listener.start()
                server = listener
            } catch {
                note = .init(ok: false, text: "Could not serve the docs", fix: error.localizedDescription)
            }
        }
    }

    func openSource(_ path: String) {
        guard Self.isSourcePath(path) else { return }
        sourcePath = path
        navigationRevision += 1
        openCanon()
    }

    func observePage(_ page: URL?) {
        guard let url, let page, page.scheme == url.scheme, page.host == url.host, page.port == url.port else {
            displayedURL = nil
            currentSource = nil
            return
        }
        displayedURL = page
        let path = page.path(percentEncoded: true).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        currentSource = Self.isSourcePath(path) ? path : nil
    }

    private static func isSourcePath(_ path: String) -> Bool {
        path.range(of: #"^(standards|skills)/[a-z0-9][a-z0-9._-]*/$"#, options: .regularExpression) != nil
    }

    func openInBrowser() {
        guard let url = displayedURL ?? pageURL, !openURL(url) else { return }
        note = .init(ok: false, text: "Could not open the browser", fix: "Open \(url.absoluteString) in your browser.")
    }

    func refresh() {
        build(openAfter: url == nil)
    }

    private func build(openAfter: Bool) {
        guard !building else { return }
        building = true
        note = nil
        let buildSite = rebuild
        let cache = self.cache
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try buildSite(cache) }.value
                builtAt = Self.buildDate(site)
                revision += 1
                note = .init(ok: true, text: "Canon and team skills are up to date")
            } catch {
                note = .init(ok: false, text: "Could not build the docs", fix: error.localizedDescription)
            }
            building = false
            if openAfter, note?.ok == true { openCanon() }
        }
    }

    private static func buildDate(_ site: URL) -> Date? {
        let index = site.appendingPathComponent("index.html")
        return try? index.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

enum DocsBuild {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func cacheDirectory(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["GREAT_GUI_DOCS_CACHE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL.cachesDirectory.appendingPathComponent("com.cwkoenigs.the-great-gui/Docs", isDirectory: true)
    }

    static func toolEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let userBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        environment["PATH"] = [environment["PATH"], userBin, "/opt/homebrew/bin", "/usr/local/bin"]
            .compactMap { $0 }.joined(separator: ":")
        return environment
    }

    /// Build outside any project, then publish the complete site without replacing a good build on failure.
    static func rebuild(in cache: URL, command: String = "exec ds-next docs --out") throws {
        let fm = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try fm.createDirectory(at: cache, withIntermediateDirectories: true, attributes: attributes)
        let candidate = cache.appendingPathComponent("build-\(UUID().uuidString)", isDirectory: true)
        let staging = fm.temporaryDirectory.appendingPathComponent("great-gui-docs-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: attributes)
        defer {
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: candidate)
        }

        let log = staging.appendingPathComponent("build.log")
        try Data().write(to: log)
        let output = try FileHandle(forUpdating: log)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessRun.defaultShell())
        process.arguments = ["-lc", command + " " + Registry.shellQuote(candidate.path)]
        process.currentDirectoryURL = staging
        var environment = toolEnvironment()
        environment["TMPDIR"] = staging.path
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let end = try output.seekToEnd()
            try output.seek(toOffset: end > 4096 ? end - 4096 : 0)
            let tail = Ansi.strip(String(decoding: try output.readToEnd() ?? Data(), as: UTF8.self))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fix = process.terminationStatus == 127
                ? "Install ds-next and make it available on PATH."
                : (tail.isEmpty ? "ds-next exited with code \(process.terminationStatus)." : tail)
            throw Failure(message: fix)
        }
        guard fm.fileExists(atPath: candidate.appendingPathComponent("index.html").path) else {
            throw Failure(message: "ds-next did not produce an index.html.")
        }

        let site = cache.appendingPathComponent("site", isDirectory: true)
        if !fm.fileExists(atPath: site.path) {
            do {
                try fm.moveItem(at: candidate, to: site)
                return
            } catch {
                guard fm.fileExists(atPath: site.path) else { throw error }
            }
        }
        // The listener can keep reading the same path while the two directories are exchanged.
        guard renameatx_np(AT_FDCWD, candidate.path, AT_FDCWD, site.path, UInt32(RENAME_SWAP)) == 0 else {
            throw Failure(message: "Could not replace the cached docs: \(String(cString: strerror(errno))).")
        }
    }
}
