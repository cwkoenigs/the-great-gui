import Foundation

/// The one way a command is added, shared by the window, the command line and the skill: build it from
/// text, validate it exactly as the loader would, append one block to the file as it is (comments and
/// hand-written entries untouched), re-read, and commit when the folder is a git repository.
public enum RegistryWriter {
    /// `name:description=default!` — description and default are optional; a trailing `!` means required.
    public static func parseParam(_ spec: String) throws -> Param {
        var s = Substring(spec.trimmingCharacters(in: .whitespaces))
        var required = false
        if s.hasSuffix("!") {
            required = true
            s = s.dropLast()
        }
        var defaultValue: String?
        if let eq = s.firstIndex(of: "=") {
            defaultValue = String(s[s.index(after: eq)...])
            s = s[..<eq]
        }
        var desc = ""
        if let colon = s.firstIndex(of: ":") {
            desc = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            s = s[..<colon]
        }
        let name = String(s).trimmingCharacters(in: .whitespaces)
        guard Registry.isValidParamName(name) else {
            throw RegistryError("'\(name)' is not a valid parameter name", fix: "lowercase letters, digits and _, as in  seconds:how long=3600!")
        }
        return Param(name: name, desc: desc, defaultValue: defaultValue, required: required)
    }

    /// Several parameters in one field, separated by `;`.
    public static func parseParams(_ field: String) throws -> [Param] {
        try field.split(separator: ";").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(parseParam)
    }

    /// `KEY=value` or `KEY=keychain:NAME`.
    public static func parseEnv(_ spec: String) throws -> (key: String, value: EnvValue) {
        let s = spec.trimmingCharacters(in: .whitespaces)
        guard let eq = s.firstIndex(of: "="), eq > s.startIndex else {
            throw RegistryError("'\(s)' is not KEY=value", fix: "an environment entry is KEY=value, or KEY=keychain:NAME for a secret")
        }
        let key = String(s[..<eq])
        guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
            throw RegistryError("'\(key)' is not a valid environment variable name", fix: "letters, digits and _")
        }
        return (key, EnvValue(String(s[s.index(after: eq)...])))
    }

    /// Several entries in one field, separated by `;`.
    public static func parseEnvs(_ field: String) throws -> [String: EnvValue] {
        var out: [String: EnvValue] = [:]
        for part in field.split(separator: ";").map(String.init) where !part.trimmingCharacters(in: .whitespaces).isEmpty {
            let (k, v) = try parseEnv(part)
            out[k] = v
        }
        return out
    }

    /// `keychain:NAME`, or just `NAME`; empty for none. The name is the Keychain item holding the `.env`.
    public static func parseEnvFile(_ field: String) throws -> String? {
        let s = field.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        let name = s.hasPrefix(EnvValue.keychainPrefix) ? String(s.dropFirst(EnvValue.keychainPrefix.count)) : s
        guard Registry.isValidSecretName(name) else {
            throw RegistryError("'\(s)' is not keychain:NAME", fix: "env_file names a .env kept in the Keychain: letters, digits, . _ and -")
        }
        return name
    }

    /// Tags separated by commas or spaces.
    public static func parseTags(_ field: String) -> [String] {
        field.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { !$0.isEmpty }
    }

    /// "yes", "y", "true", "1" and "on" are true; "", "no", "n", "false", "0" and "off" are false.
    public static func parseBool(_ field: String, name: String) throws -> Bool {
        switch field.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yes", "y", "true", "1", "on": true
        case "", "no", "n", "false", "0", "off": false
        default: throw RegistryError("\(name) must be yes or no", fix: "it is '\(field)'")
        }
    }

    /// A command from text, validated exactly as the loader validates a file: the block is rendered
    /// and parsed, so every rule and every message is the loader's.
    public static func build(name: String, run: String, desc: String = "", group: String = "", cwd: String = "",
                             interactive: Bool = false, gate: Bool = false, tags: [String] = [],
                             env: [String: EnvValue] = [:], params: [Param] = [], schedule: String = "",
                             envFile: String = "") throws -> Command {
        let when = try schedule.trimmingCharacters(in: .whitespaces).nilIfEmpty.map { try Schedule($0) }
        let draft = Command(name: name.trimmingCharacters(in: .whitespaces), group: group.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "commands",
                            desc: desc.trimmingCharacters(in: .whitespaces), run: run.trimmingCharacters(in: .whitespaces),
                            cwd: cwd.trimmingCharacters(in: .whitespaces).nilIfEmpty, interactive: interactive, gate: gate,
                            tags: tags, env: env, params: params, schedule: when, envFile: try parseEnvFile(envFile))
        guard !draft.name.isEmpty else { throw RegistryError("the command needs a name", fix: "lowercase letters, digits, . _ and -") }
        guard !draft.run.isEmpty else { throw RegistryError("\(draft.name) needs a run line", fix: "the shell command it runs") }
        let parsed = try Registry.parse(render(draft), url: URL(fileURLWithPath: "new-command.toml"))
        return parsed.commands[0]
    }

    // MARK: rendering

    public static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case let c where c.value < 0x20 || c.value == 0x7f: out += String(format: "\\u%04X", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// One `[[command]]` block, keys in the README's order, only the keys that carry something.
    public static func render(_ c: Command) -> String {
        var lines = ["[[command]]", "name = \(quote(c.name))"]
        if c.group != "commands" { lines.append("group = \(quote(c.group))") }
        if !c.desc.isEmpty { lines.append("desc = \(quote(c.desc))") }
        lines.append("run = \(quote(c.run))")
        if let cwd = c.cwd, !cwd.isEmpty { lines.append("cwd = \(quote(cwd))") }
        if c.interactive { lines.append("interactive = true") }
        if c.gate { lines.append("gate = true") }
        if let s = c.schedule { lines.append("schedule = \(quote(s.text))") }
        if !c.tags.isEmpty { lines.append("tags = [" + c.tags.map(quote).joined(separator: ", ") + "]") }
        if !c.env.isEmpty {
            let entries = c.env.sorted { $0.key < $1.key }.map { "\($0.key) = \(quote($0.value.display))" }
            lines.append("env = { " + entries.joined(separator: ", ") + " }")
        }
        if let f = c.envFile { lines.append("env_file = \(quote(EnvValue.keychainPrefix + f))") }
        for p in c.params {
            lines.append("[[command.param]]")
            lines.append("name = \(quote(p.name))")
            if !p.desc.isEmpty { lines.append("desc = \(quote(p.desc))") }
            if let d = p.defaultValue { lines.append("default = \(quote(d))") }
            if p.required { lines.append("required = true") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One `[[file]]` block: the pointer to a credential file, never its contents.
    public static func render(_ f: SecretFile) -> String {
        var lines = ["[[file]]", "name = \(quote(f.name))", "path = \(quote(f.path))"]
        if f.mode != SecretFile.defaultMode { lines.append("mode = \(quote(f.mode))") }
        if !f.desc.isEmpty { lines.append("desc = \(quote(f.desc))") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One `[[tool]]` block, only the keys that carry something.
    public static func render(_ t: Tool) -> String {
        var lines = ["[[tool]]", "name = \(quote(t.name))"]
        if !t.desc.isEmpty { lines.append("desc = \(quote(t.desc))") }
        lines.append("method = \(quote(t.method.rawValue))")
        if t.method != .script, t.pkg != t.name { lines.append("pkg = \(quote(t.pkg))") }
        if let bin = t.bin, !(t.method == .script && bin == t.name) { lines.append("bin = \(quote(bin))") }
        if let install = t.install { lines.append("install = \(quote(install))") }
        if let update = t.update { lines.append("update = \(quote(update))") }
        if !t.requires.isEmpty { lines.append("requires = [" + t.requires.map(quote).joined(separator: ", ") + "]") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A tool from text, validated exactly as the loader validates one.
    public static func buildTool(name: String, method: String, desc: String = "", pkg: String = "", bin: String = "",
                                 install: String = "", update: String = "", requires: [String] = []) throws -> Tool {
        var lines = ["[[tool]]", "name = \(quote(name.trimmingCharacters(in: .whitespaces)))", "method = \(quote(method))", "desc = \(quote(desc.trimmingCharacters(in: .whitespaces)))"]
        if !pkg.isEmpty { lines.append("pkg = \(quote(pkg))") }
        if !bin.isEmpty { lines.append("bin = \(quote(bin))") }
        if !install.isEmpty { lines.append("install = \(quote(install))") }
        if !update.isEmpty { lines.append("update = \(quote(update))") }
        if !requires.isEmpty { lines.append("requires = [" + requires.map(quote).joined(separator: ", ") + "]") }
        return try Registry.parse(lines.joined(separator: "\n") + "\n", url: URL(fileURLWithPath: "new-tool.toml")).tools[0]
    }

    /// Appends the tool (creating the registry when absent). A name that exists is refused.
    @discardableResult
    public static func appendTool(_ t: Tool, to url: URL) throws -> Registry {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Registry(url: url, commands: []) : try Registry.parse(existing, url: url)
        if current.tool(named: t.name) != nil {
            throw RegistryError("a tool named \(t.name) exists", fix: "pick another name, or great-gui tools remove \(t.name) first")
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
        let text = existing + separator + render(t)
        let registry = try Registry.parse(text, url: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return registry
    }

    /// A file pointer from text, validated exactly as the loader validates one.
    public static func buildFile(name: String, path: String, mode: String = "", desc: String = "") throws -> SecretFile {
        let draft = SecretFile(name: name.trimmingCharacters(in: .whitespaces), path: path.trimmingCharacters(in: .whitespaces),
                               mode: mode.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? SecretFile.defaultMode,
                               desc: desc.trimmingCharacters(in: .whitespaces))
        guard !draft.name.isEmpty else { throw RegistryError("the file needs a name", fix: "letters, digits, . _ and -; it names the Keychain item") }
        guard !draft.path.isEmpty else { throw RegistryError("\(draft.name) needs a path", fix: "where the file belongs, as in ~/.snowflake/connections.toml") }
        // The mode is rendered even when it is the default, so a bad one is the loader's to refuse.
        let block = "[[file]]\nname = \(quote(draft.name))\npath = \(quote(draft.path))\nmode = \(quote(draft.mode))\ndesc = \(quote(draft.desc))\n"
        return try Registry.parse(block, url: URL(fileURLWithPath: "new-file.toml")).files[0]
    }

    /// The path as a registry should carry it: the home directory written as `~`.
    public static func portable(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: writing

    /// Appends the file pointer (creating the registry when absent). A name that exists is refused.
    @discardableResult
    public static func appendFile(_ f: SecretFile, to url: URL) throws -> Registry {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Registry(url: url, commands: []) : try Registry.parse(existing, url: url)
        if current.file(named: f.name) != nil {
            throw RegistryError("a file named \(f.name) exists", fix: "pick another name, or great-gui file remove \(f.name) first")
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
        let text = existing + separator + render(f)
        let registry = try Registry.parse(text, url: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return registry
    }

    /// Appends the command to the file (creating it when absent), validates the whole file before
    /// writing, and returns the registry as it now is. A name that exists is refused.
    @discardableResult
    public static func append(_ c: Command, to url: URL) throws -> Registry {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Registry(url: url, commands: []) : try Registry.parse(existing, url: url)
        if current.command(named: c.name) != nil {
            throw RegistryError("a command named \(c.name) exists", fix: "pick another name, or edit the one in \(url.lastPathComponent)")
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n")
        let text = existing + separator + render(c)
        let registry = try Registry.parse(text, url: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return registry
    }

    // MARK: git

    /// True when the file's folder is a git repository.
    public static func isRepository(_ url: URL) -> Bool {
        git(["rev-parse", "--is-inside-work-tree"], in: url.deletingLastPathComponent()).status == 0
    }

    /// Commits the file in its folder's repository, if there is one and the file changed. Never pushes.
    @discardableResult
    public static func autoCommit(_ url: URL, message: String) -> Bool {
        let dir = url.deletingLastPathComponent()
        guard isRepository(url) else { return false }
        guard git(["add", "--", url.lastPathComponent], in: dir).status == 0 else { return false }
        return git(["commit", "-q", "-m", message, "--", url.lastPathComponent], in: dir).status == 0
    }

    static func git(_ args: [String], in dir: URL) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (127, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
