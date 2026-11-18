import Foundation

/// What a whole-file secret could not do. `what` names it, `fix` says what to do. Never a value.
public struct FileSecretError: Error, Equatable, CustomStringConvertible, Sendable {
    public let what: String
    public let fix: String
    public init(_ what: String, fix: String = "") { self.what = what; self.fix = fix }
    public var description: String { fix.isEmpty ? what : "\(what)\n  \(fix)" }
}

/// Credential files kept whole in the Keychain: a `.env`, a `connections.toml`, a key file. The bytes are
/// one generic-password item under the file's name, in the same service as every other secret; this type
/// moves them between that item and a path, and says how the two compare. It never returns, logs or
/// prints the bytes, and nothing here sends them anywhere: a file's secret stays on the Mac it was stored on.
public struct FileSecrets: Sendable {
    public let store: SecretStore

    /// A credential file is small; anything larger is a mistake (a database, a log).
    public static let maxBytes = 1_048_576

    public init(store: SecretStore = SecretStore()) { self.store = store }

    /// How the Keychain copy and the file on disk compare.
    public enum State: String, Equatable, Sendable {
        /// Same bytes, private mode.
        case inSync
        /// Same bytes, but the file's permissions are not the mode asked for.
        case wrongMode
        /// Both exist and their bytes are not the same.
        case differs
        /// In the Keychain; no file at the path.
        case notOnDisk
        /// A file at the path; nothing in the Keychain yet.
        case notStored
        /// Neither.
        case missing

        /// What it means and what to do, in one line.
        public var advice: String {
            switch self {
            case .inSync: "The file and its Keychain copy match. Nothing to do."
            case .wrongMode: "Contents match, but other users could read the file. Restore fixes the mode."
            case .differs: "The file changed since it was stored. Store keeps the file's version; restore with force puts the Keychain's back."
            case .notOnDisk: "Stored in the Keychain, but the file is not at its path. Restore writes it."
            case .notStored: "The file exists but is not in the Keychain yet. Store keeps it."
            case .missing: "Not stored, and no file at the path. Create the file, then store it."
            }
        }

        public var words: String {
            switch self {
            case .inSync: "in sync"
            case .wrongMode: "wrong mode"
            case .differs: "differs"
            case .notOnDisk: "not on this Mac"
            case .notStored: "not stored"
            case .missing: "missing"
            }
        }
    }

    public enum Restored: Equatable, Sendable {
        case written(bytes: Int)
        case modeFixed
        case unchanged
    }

    /// Compares the two. Reading the Keychain copy may prompt the first time a build does it.
    public func state(name: String, path: String, mode: UInt16 = 0o600) throws -> State {
        let onDisk = try Self.read(path)
        let stored: Data?
        do { stored = try store.data(name) } catch SecretStore.Failure.notFound { stored = nil }
        switch (stored, onDisk) {
        case (nil, nil): return .missing
        case (nil, .some): return .notStored
        case (.some, nil): return .notOnDisk
        case (.some(let a), .some(let b)):
            if a != b { return .differs }
            return Self.mode(of: path) == mode ? .inSync : .wrongMode
        }
    }

    /// The file's bytes into the Keychain. Returns how many, and whether an older copy was replaced.
    @discardableResult
    public func keep(name: String, from path: String) throws -> (bytes: Int, replaced: Bool) {
        guard let data = try Self.read(path) else {
            throw FileSecretError("there is no file at \(path)", fix: "create it first; its contents are what gets stored")
        }
        guard !data.isEmpty else { throw FileSecretError("\(path) is empty", fix: "an empty file is not worth a Keychain item") }
        return (data.count, try store.setData(name, data))
    }

    /// The Keychain copy onto the path, atomically, at `mode`. A file whose bytes differ is left alone unless `force`.
    @discardableResult
    public func restore(name: String, to path: String, mode: UInt16 = 0o600, force: Bool = false) throws -> Restored {
        guard mode & 0o077 == 0 else {
            throw FileSecretError("mode \(String(mode, radix: 8)) lets other users read the file", fix: "a credential file is 600 or 400")
        }
        let data = try store.data(name)
        if let onDisk = try Self.read(path) {
            if onDisk == data {
                if Self.mode(of: path) == mode { return .unchanged }
                guard chmod(path, mode_t(mode)) == 0 else { throw Self.posix("could not set the mode of \(path)") }
                return .modeFixed
            }
            guard force else {
                throw FileSecretError("\(path) differs from the Keychain copy",
                                      fix: "store keeps the file's version; restore with force overwrites the file")
            }
        }
        try Self.write(data, to: path, mode: mode)
        return .written(bytes: data.count)
    }

    // MARK: the disk

    /// The file's bytes, or nil when nothing is there. A directory, or a file past the size limit, is an error.
    static func read(_ path: String) throws -> Data? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        guard !isDir.boolValue else { throw FileSecretError("\(path) is a folder", fix: "a file secret is one file") }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= maxBytes else {
            throw FileSecretError("\(path) is \(size) bytes", fix: "a file secret holds up to \(maxBytes) bytes; this is not a credential file")
        }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw FileSecretError("could not read \(path): \(error.localizedDescription)")
        }
    }

    static func mode(of path: String) -> UInt16? {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber).map { $0.uint16Value & 0o777 }
    }

    /// A private temporary file beside the target, then a rename: no reader ever sees half a file, and the
    /// bytes are never on disk at a wider mode. Folders this creates are the owner's alone.
    static func write(_ data: Data, to path: String, mode: UInt16) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                throw FileSecretError("could not create \(dir.path): \(error.localizedDescription)")
            }
        }
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).tmp").path
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw posix("could not write in \(dir.path)") }
        var failure: FileSecretError?
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    failure = Self.posix("could not write \(path)")
                    return
                }
                offset += n
            }
        }
        if failure == nil, fchmod(fd, mode_t(mode)) != 0 { failure = posix("could not set the mode of \(path)") }
        close(fd)
        if failure == nil, rename(temp, path) != 0 { failure = posix("could not replace \(path)") }
        if let failure {
            unlink(temp)
            throw failure
        }
    }

    static func posix(_ what: String) -> FileSecretError {
        FileSecretError(what + ": " + String(cString: strerror(errno)))
    }
}

/// A `.env` as text: `KEY=value` lines, `#` comments, an optional `export`, single or double quotes.
/// Errors name the line number and never quote the line, so a value cannot reach a message.
public enum DotEnv {
    public static func parse(_ text: String) throws -> [(key: String, value: String)] {
        var out: [(String, String)] = []
        for (i, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }).enumerated() {
            var line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export "), line.dropFirst(7).contains("=") { line = Substring(line.dropFirst(7).trimmingCharacters(in: .whitespaces)) }
            guard let eq = line.firstIndex(of: "=") else {
                throw FileSecretError("line \(i + 1) of the env file is not KEY=value", fix: "every line is KEY=value, a # comment, or blank")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw FileSecretError("line \(i + 1) of the env file has a name that is not letters, digits and _", fix: "as in API_KEY=…")
            }
            let rest = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            out.append((key, try value(rest, line: i + 1)))
        }
        return out
    }

    static func value(_ s: String, line: Int) throws -> String {
        guard let first = s.first else { return "" }
        if first == "'" {
            guard let end = s.dropFirst().firstIndex(of: "'") else { throw unterminated(line) }
            return String(s[s.index(after: s.startIndex)..<end])
        }
        if first == "\"" {
            var out = ""
            var i = s.index(after: s.startIndex)
            while i < s.endIndex {
                let c = s[i]
                if c == "\"" { return out }
                if c == "\\", s.index(after: i) < s.endIndex {
                    i = s.index(after: i)
                    switch s[i] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    default: out.append(s[i])   // \" \\ \$ and anything else: the character itself
                    }
                } else {
                    out.append(c)
                }
                i = s.index(after: i)
            }
            throw unterminated(line)
        }
        // Unquoted: up to a comment that follows a space.
        if let hash = s.range(of: " #") { return s[..<hash.lowerBound].trimmingCharacters(in: .whitespaces) }
        return s
    }

    static func unterminated(_ line: Int) -> FileSecretError {
        FileSecretError("line \(line) of the env file opens a quote and never closes it", fix: "a quoted value ends on its own line")
    }
}
