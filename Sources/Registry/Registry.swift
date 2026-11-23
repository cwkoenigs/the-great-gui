import Foundation
import TOMLKit

/// One entry of commands.toml: a shell line with a name, a group and a description; parameters that
/// become a form; the directory it runs in; whether it needs a terminal; the environment it gets, where a
/// value `keychain:NAME` is a secret the app fetches at run time; and whether a run is gated behind
/// Touch ID or the login password. `envFile` names a whole `.env` kept in the Keychain: its entries join
/// the environment at run time and the file is never written to disk.
public struct Command: Equatable, Sendable {
    public var name: String
    public var group: String
    public var desc: String
    public var run: String
    public var cwd: String?
    public var interactive: Bool
    public var gate: Bool
    public var tags: [String]
    public var env: [String: EnvValue]
    public var params: [Param]
    /// When it runs on its own; nil for a command that runs only when asked.
    public var schedule: Schedule?
    /// The Keychain name of a `.env` whose entries join the environment; nil for none.
    public var envFile: String?
    /// Whose it is: the person's own file, or the team's, which is read-only here (Team.swift).
    public var origin: Origin = .personal
    /// A personal command with the name of a team one: it wins, and the window says so.
    public var overridesTeam = false
    /// A team command's schedule, held back: nothing the team sends runs by itself. A copy of yours can arm it.
    public var teamSchedule: Schedule?

    public init(name: String, group: String = "commands", desc: String = "", run: String, cwd: String? = nil,
                interactive: Bool = false, gate: Bool = false, tags: [String] = [], env: [String: EnvValue] = [:], params: [Param] = [],
                schedule: Schedule? = nil, envFile: String? = nil) {
        self.name = name; self.group = group; self.desc = desc; self.run = run; self.cwd = cwd
        self.interactive = interactive; self.gate = gate; self.tags = tags; self.env = env; self.params = params
        self.schedule = schedule; self.envFile = envFile
    }

    /// The secrets this command needs, by Keychain name: its env file first, then its env values in key order.
    public var secretNames: [String] { Self.secretNames(env: env, envFile: envFile) }

    static func secretNames(env: [String: EnvValue], envFile: String?) -> [String] {
        var out = envFile.map { [$0] } ?? []
        for (_, v) in env.sorted(by: { $0.key < $1.key }) {
            if case .keychain(let n) = v, !out.contains(n) { out.append(n) }
        }
        return out
    }
}

/// One `[[file]]` entry: a credential file kept whole in the Keychain under `name`, and where it belongs
/// on disk. The registry holds the pointer only; the bytes never appear in it.
public struct SecretFile: Equatable, Sendable, Identifiable {
    public var name: String
    /// As written, usually with `~`, so a shared registry carries nobody's home directory.
    public var path: String
    /// Octal permission bits, owner only: 600 unless the entry says otherwise.
    public var mode: String
    public var desc: String
    /// True for a pointer the team's registry brought: a checklist entry, read-only here.
    public var team = false
    public var id: String { name }

    public static let defaultMode = "600"

    public init(name: String, path: String, mode: String = SecretFile.defaultMode, desc: String = "") {
        self.name = name; self.path = path; self.mode = mode; self.desc = desc
    }

    /// The path with `~` expanded.
    public var expandedPath: String { NSString(string: path).expandingTildeInPath }
    public var modeBits: UInt16 { UInt16(mode, radix: 8) ?? 0o600 }
}

public struct Param: Equatable, Sendable {
    public var name: String
    public var desc: String
    public var defaultValue: String?
    public var required: Bool
    public init(name: String, desc: String = "", defaultValue: String? = nil, required: Bool = false) {
        self.name = name; self.desc = desc; self.defaultValue = defaultValue; self.required = required
    }
}

/// An environment value: literal text, or a secret fetched from the Keychain by name.
public enum EnvValue: Equatable, Sendable {
    case literal(String)
    case keychain(String)

    public static let keychainPrefix = "keychain:"

    public init(_ raw: String) {
        if raw.hasPrefix(Self.keychainPrefix), raw.count > Self.keychainPrefix.count {
            self = .keychain(String(raw.dropFirst(Self.keychainPrefix.count)))
        } else {
            self = .literal(raw)
        }
    }

    /// True when the value comes from the Keychain at run time.
    public var isSecret: Bool { if case .keychain = self { true } else { false } }

    /// How the registry shows it: never the value of a secret, only where it comes from.
    public var display: String {
        switch self {
        case .literal(let s): s
        case .keychain(let n): Self.keychainPrefix + n
        }
    }
}

/// A command with its parameters filled in: what the runner or the terminal gets.
public struct Resolved: Equatable, Sendable {
    public let name: String
    public let run: String
    public let cwd: String?
    public let env: [String: EnvValue]
    public let interactive: Bool
    public let gate: Bool
    public var envFile: String? = nil
    public var secretNames: [String] { Command.secretNames(env: env, envFile: envFile) }

    /// A run that is not in the registry (`great-gui exec`): the line is taken as it is, with no `{param}`.
    public init(name: String, run: String, cwd: String? = nil, env: [String: EnvValue] = [:],
                interactive: Bool = false, gate: Bool = false, envFile: String? = nil) {
        self.name = name; self.run = run; self.cwd = cwd; self.env = env
        self.interactive = interactive; self.gate = gate; self.envFile = envFile
    }
}

/// What the registry could not use. `what` names it, `fix` says what to do.
public struct RegistryError: Error, Equatable, CustomStringConvertible, Sendable {
    public let what: String
    public let fix: String
    public init(_ what: String, fix: String = "") { self.what = what; self.fix = fix }
    public var description: String { fix.isEmpty ? what : "\(what)\n  \(fix)" }
}

public struct Registry: Equatable, Sendable {
    public let url: URL
    public let commands: [Command]
    /// The credential files the registry points at, in file order.
    public let files: [SecretFile]
    /// The team's registry as it was merged in, or why it could not be; nil when this Mac has none.
    public var team: TeamState?
    /// The programs this Mac should have, in file order (Tools.swift).
    public let tools: [Tool]

    public init(url: URL, commands: [Command], files: [SecretFile] = [], tools: [Tool] = []) {
        self.url = url; self.commands = commands; self.files = files; self.tools = tools
    }

    public func file(named name: String) -> SecretFile? { files.first { $0.name == name } }

    /// Groups in order of first appearance.
    public var groups: [String] {
        var seen: [String] = []
        for c in commands where !seen.contains(c.group) { seen.append(c.group) }
        return seen
    }

    public func command(named name: String) -> Command? { commands.first { $0.name == name } }

    /// Case-insensitive match on name, description, group and tags; an empty query is everything.
    public func filtered(_ query: String) -> [Command] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { c in
            c.name.lowercased().contains(q) || c.desc.lowercased().contains(q) || c.group.lowercased().contains(q)
                || c.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: Resolution

    static let placeholder = try! NSRegularExpression(pattern: "\\{([a-z_][a-z0-9_]*)\\}")

    static func placeholders(in s: String) -> [String] {
        placeholder.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range(at: 1), in: s)!]) }
    }

    /// Substitutes `{name}`; `quote` shell-quotes each value (for `run`), otherwise it is a path (`cwd`).
    static func substitute(_ template: String, values: [String: String], quote: Bool, keep: Set<String> = []) throws -> String {
        var out = ""
        var last = template.startIndex
        for m in placeholder.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            let whole = Range(m.range, in: template)!, key = String(template[Range(m.range(at: 1), in: template)!])
            out += template[last..<whole.lowerBound]
            if keep.contains(key) {
                out += template[whole]
            } else if let v = values[key] {
                out += quote ? shellQuote(v) : v
            } else {
                throw RegistryError("{\(key)} is not a parameter", fix: "declare it as a [[command.param]]")
            }
            last = whole.upperBound
        }
        out += template[last...]
        return out
    }

    public static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_~")
        if s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// The command as it would run. `partial` leaves a parameter nobody gave as `{name}`, for previews.
    public func resolve(_ cmd: Command, params given: [String: String] = [:], partial: Bool = false) throws -> Resolved {
        let declared = Set(cmd.params.map(\.name))
        if let stray = given.keys.first(where: { !declared.contains($0) }) {
            throw RegistryError("\(cmd.name) has no parameter \(stray)", fix: "its parameters are " + (cmd.params.map(\.name).joined(separator: ", ").nilIfEmpty ?? "none"))
        }
        var values: [String: String] = [:]
        var missing: Set<String> = []
        for p in cmd.params {
            if let v = given[p.name], !v.isEmpty {
                values[p.name] = v
            } else if let d = p.defaultValue {
                values[p.name] = d
            } else if partial {
                missing.insert(p.name)
            } else if p.required {
                throw RegistryError("\(cmd.name) needs \(p.name)", fix: p.desc.nilIfEmpty ?? "fill it in and run again")
            } else {
                values[p.name] = ""
            }
        }
        let run = try Self.substitute(cmd.run, values: values, quote: true, keep: missing)
        var cwd = cmd.cwd.map { try? Self.substitute($0, values: values, quote: false, keep: missing) } ?? nil
        cwd = cwd.map { NSString(string: $0).expandingTildeInPath }
        return Resolved(name: cmd.name, run: run, cwd: cwd, env: cmd.env, interactive: cmd.interactive, gate: cmd.gate, envFile: cmd.envFile)
    }

    public func preview(_ cmd: Command) -> Resolved? { try? resolve(cmd, partial: true) }

    // MARK: Loading

    public static let nameRule = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9._-]*$")

    public static func isValidName(_ name: String) -> Bool {
        nameRule.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// A Keychain item's name, as the Secrets module takes it: letters, digits, . _ and -.
    public static func isValidSecretName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }

    /// A parameter name is also a `{placeholder}`: lowercase letters, digits and _.
    public static func isValidParamName(_ name: String) -> Bool {
        name.range(of: "^[a-z_][a-z0-9_]*$", options: .regularExpression) != nil
    }

    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let p = environment["GREAT_GUI_REGISTRY"], !p.isEmpty {
            return URL(fileURLWithPath: NSString(string: p).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".great-gui/commands.toml")
    }

    /// The example registry that ships with the app: what a fresh install starts from.
    public static func exampleTOML() -> String {
        guard let url = Bundle.module.url(forResource: "commands.example", withExtension: "toml"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "# commands.toml\n" }
        return text
    }

    public static func load(from url: URL = defaultURL()) throws -> Registry {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RegistryError("no registry at \(url.path)", fix: "the app writes an example there on first launch; or set GREAT_GUI_REGISTRY")
        }
        return try parse(text, url: url)
    }

    public static func parse(_ text: String, url: URL = URL(fileURLWithPath: "commands.toml")) throws -> Registry {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: text)
        } catch let e as TOMLParseError {
            throw RegistryError("\(url.lastPathComponent): \(e.description) at line \(e.source.begin.line)", fix: "fix the TOML; nothing was changed")
        }
        let file: RegistryFile
        do {
            file = try TOMLDecoder(strictDecoding: true).decode(RegistryFile.self, from: table)
        } catch let e as UnexpectedKeysError {
            let (key, path) = e.keys.sorted { $0.key < $1.key }.first!
            let inFile = path.first?.stringValue == "file"
            let inTool = path.first?.stringValue == "tool"
            let inParam = path.contains { $0.stringValue == "param" }
            let allowed = path.dropLast(key).isEmpty ? ["command", "file", "tool"]
                : inFile ? FileSpec.CodingKeys.allCases.map(\.rawValue)
                : inTool ? ToolSpec.CodingKeys.allCases.map(\.rawValue)
                : inParam ? ["name", "desc", "default", "required"]
                : CommandSpec.CodingKeys.allCases.map(\.rawValue)
            throw RegistryError("\(describe(path.dropLast(key))): unknown key \(key)", fix: "allowed: " + allowed.joined(separator: ", "))
        } catch let e as DecodingError {
            throw RegistryError(describe(e, in: table), fix: "fix the entry in \(url.lastPathComponent)")
        }
        var commands: [Command] = []
        var seen: Set<String> = []
        for (i, spec) in file.command.enumerated() {
            let where_ = "command[\(i)]"
            guard nameRule.firstMatch(in: spec.name, range: NSRange(spec.name.startIndex..., in: spec.name)) != nil else {
                throw RegistryError("\(where_): '\(spec.name)' is not a valid name", fix: "lowercase letters, digits, . _ and -")
            }
            guard seen.insert(spec.name).inserted else {
                throw RegistryError("two commands are named \(spec.name)", fix: "names are how the window finds a command")
            }
            guard !spec.run.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw RegistryError("\(spec.name) has an empty run", fix: "run is the shell line")
            }
            var params: [Param] = []
            for p in spec.param ?? [] {
                guard isValidParamName(p.name) else {
                    throw RegistryError("\(spec.name): parameter '\(p.name)' is not a valid name", fix: "lowercase letters, digits and _")
                }
                params.append(Param(name: p.name, desc: p.desc ?? "", defaultValue: p.default, required: p.required ?? false))
            }
            let declared = Set(params.map(\.name))
            for ph in placeholders(in: spec.run) + placeholders(in: spec.cwd ?? "") where !declared.contains(ph) {
                throw RegistryError("\(spec.name) uses {\(ph)} but declares no such parameter", fix: "add a [[command.param]] named \(ph)")
            }
            let env = (spec.env ?? [:]).mapValues(EnvValue.init)
            var envFile: String?
            if let raw = spec.envFile?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
                guard case .keychain(let n) = EnvValue(raw), isValidSecretName(n) else {
                    throw RegistryError("\(spec.name): env_file must be keychain:NAME", fix: "the .env lives in the Keychain: great-gui file add NAME --path .env, then env_file = \"keychain:NAME\"")
                }
                envFile = n
            }
            var schedule: Schedule?
            if let s = spec.schedule?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                do {
                    schedule = try Schedule(s)
                } catch let e as RegistryError {
                    throw RegistryError("\(spec.name): \(e.what)", fix: e.fix)
                }
                if spec.gate ?? false {
                    throw RegistryError("\(spec.name) is gated and scheduled", fix: "Touch ID needs the window: drop gate or the schedule")
                }
                if spec.interactive ?? false {
                    throw RegistryError("\(spec.name) is interactive and scheduled", fix: "a scheduled run has no terminal: drop interactive or the schedule")
                }
                if let p = params.first(where: { $0.defaultValue == nil }) {
                    throw RegistryError("\(spec.name) is scheduled but its parameter \(p.name) has no default", fix: "a scheduled run fills parameters from their defaults")
                }
            }
            commands.append(Command(name: spec.name, group: spec.group ?? "commands", desc: spec.desc ?? "", run: spec.run, cwd: spec.cwd,
                                    interactive: spec.interactive ?? false, gate: spec.gate ?? false, tags: spec.tags ?? [], env: env, params: params,
                                    schedule: schedule, envFile: envFile))
        }
        var files: [SecretFile] = []
        var seenFiles: Set<String> = []
        for (i, spec) in file.file.enumerated() {
            guard isValidSecretName(spec.name) else {
                throw RegistryError("file[\(i)]: '\(spec.name)' is not a valid name", fix: "letters, digits, . _ and -")
            }
            guard seenFiles.insert(spec.name).inserted else {
                throw RegistryError("two files are named \(spec.name)", fix: "the name is the Keychain item: one per file")
            }
            let path = spec.path.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else {
                throw RegistryError("the file \(spec.name) has an empty path", fix: "path is where the file belongs, as in ~/.snowflake/connections.toml")
            }
            guard path.hasPrefix("/") || path.hasPrefix("~") else {
                throw RegistryError("the file \(spec.name) has a relative path", fix: "start it with ~ or /: ~/project/.env")
            }
            let mode = spec.mode?.trimmingCharacters(in: .whitespaces) ?? SecretFile.defaultMode
            guard mode.range(of: "^0?[0-7]{3}$", options: .regularExpression) != nil, let bits = UInt16(mode, radix: 8) else {
                throw RegistryError("the file \(spec.name): mode '\(mode)' is not three octal digits", fix: "600 is the default; 400 for read-only")
            }
            guard bits & 0o077 == 0 else {
                throw RegistryError("the file \(spec.name): mode \(mode) lets other users read it", fix: "a credential file is 600 or 400")
            }
            files.append(SecretFile(name: spec.name, path: path, mode: String(mode.suffix(3)), desc: spec.desc ?? ""))
        }
        return Registry(url: url, commands: commands, files: files, tools: try tools(from: file.tool))
    }

    static func describe(_ path: [CodingKey]) -> String {
        var out = ""
        for k in path {
            if let i = k.intValue { out += "[\(i)]" } else { out += (out.isEmpty ? "" : ".") + k.stringValue }
        }
        return out.isEmpty ? "the file" : out
    }

    /// What each key must be. The decoder reports a wrong type as a missing key, so the table is asked
    /// whether the key is there, and the schema says what it should have been.
    static func expected(_ key: String) -> String {
        switch key {
        case "interactive", "gate", "required": "true or false"
        case "tags", "requires": "a list of strings"
        case "env": "a table of strings"
        case "param": "[[command.param]] tables"
        case "command": "[[command]] tables"
        case "file": "[[file]] tables"
        case "tool": "[[tool]] tables"
        default: "a string"
        }
    }

    static func value(at path: [CodingKey], in table: TOMLTable) -> TOMLValueConvertible? {
        var current: TOMLValueConvertible = table
        for k in path {
            if let i = k.intValue {
                guard let arr = current.array, i < arr.count else { return nil }
                current = arr[i]
            } else {
                guard let tbl = current.table, let next = tbl[k.stringValue] else { return nil }
                current = next
            }
        }
        return current
    }

    static func describe(_ e: DecodingError, in table: TOMLTable) -> String {
        switch e {
        case .keyNotFound(let key, let ctx):
            let path = ctx.codingPath.dropLast(key.stringValue)
            if value(at: path + [key], in: table) != nil {
                return "\(describe(path)).\(key.stringValue) must be \(expected(key.stringValue))"
            }
            return "\(describe(path)) has no \(key.stringValue)"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            let key = ctx.codingPath.last?.stringValue ?? ""
            return "\(describe(ctx.codingPath)) must be \(expected(key))"
        case .dataCorrupted(let ctx):
            return "\(describe(ctx.codingPath)): \(ctx.debugDescription)"
        @unknown default:
            return "\(e)"
        }
    }
}

extension Array where Element == CodingKey {
    /// The path without a trailing component that names `key` (TOMLKit includes the key itself).
    func dropLast(_ key: String) -> [CodingKey] {
        if let last, last.intValue == nil, last.stringValue == key { return Array(self.dropLast()) }
        return self
    }
}

/// The file as TOMLKit decodes it; `Registry.parse` turns it into `Command`s and says what is wrong.
struct RegistryFile: Decodable {
    var command: [CommandSpec]
    var file: [FileSpec]
    var tool: [ToolSpec]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decodeIfPresent([CommandSpec].self, forKey: .command) ?? []
        file = try c.decodeIfPresent([FileSpec].self, forKey: .file) ?? []
        tool = try c.decodeIfPresent([ToolSpec].self, forKey: .tool) ?? []
    }
    enum CodingKeys: String, CodingKey { case command, file, tool }
}

struct FileSpec: Decodable {
    var name: String
    var path: String
    var mode: String?
    var desc: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case name, path, mode, desc }
}

struct CommandSpec: Decodable {
    var name: String
    var group: String?
    var desc: String?
    var run: String
    var cwd: String?
    var interactive: Bool?
    var gate: Bool?
    var tags: [String]?
    var env: [String: String]?
    var param: [ParamSpec]?
    var schedule: String?
    var envFile: String?
    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, group, desc, run, cwd, interactive, gate, tags, env, param, schedule
        case envFile = "env_file"
    }
}

struct ParamSpec: Decodable {
    var name: String
    var desc: String?
    var `default`: String?
    var required: Bool?
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
