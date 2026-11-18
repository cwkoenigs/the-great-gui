import Foundation

/// One `[[tool]]` entry: a program this Mac should have, and how it is installed and kept current. The
/// person's own file and the team's both carry them (DECISIONS local-028). Nothing here installs anything:
/// the registry says what and how, and a person or their agent asks for it.
public struct Tool: Equatable, Sendable, Identifiable {
    /// How a tool is installed. The package managers derive their lines; `script` carries its own.
    public enum Method: String, CaseIterable, Sendable {
        case brew, cask, uv, pipx, pip, npm, cargo, go, script

        public var words: String {
            switch self {
            case .brew: "Homebrew formula"
            case .cask: "Homebrew cask (an app)"
            case .uv: "uv tool (a Python program in its own environment)"
            case .pipx: "pipx (a Python program in its own environment)"
            case .pip: "pip --user (a Python library)"
            case .npm: "npm global package"
            case .cargo: "cargo install (Rust)"
            case .go: "go install; pkg is the module path, found by bin"
            case .script: "its own installer: you give the install line"
            }
        }

        /// The program the method itself needs on PATH; nil for a script, which brings its own.
        public var manager: String? {
            switch self {
            case .brew, .cask: "brew"
            case .uv: "uv"
            case .pipx: "pipx"
            case .pip: "python3"
            case .npm: "npm"
            case .cargo: "cargo"
            case .go: "go"
            case .script: nil
            }
        }

        /// Whether the manager lists what it installed. `go` and `script` tools are found on PATH by `bin`.
        public var lists: Bool { self != .script && self != .go }
        /// Whether the manager can say a tool is behind before an update is run.
        public var knowsOutdated: Bool { [.brew, .cask, .uv, .npm].contains(self) }
    }

    public var name: String
    public var desc: String
    public var method: Method
    /// What the package manager calls it; the name unless the entry says otherwise. Unused by `script`.
    public var pkg: String
    /// The program it puts on PATH. A script tool is found by it; the name unless the entry says otherwise.
    public var bin: String?
    /// `script` only: the shell line that installs it, and the one that updates it (the install line when absent).
    public var install: String?
    public var update: String?
    /// Tools or programs that must be there first.
    public var requires: [String]
    public var origin: Origin = .personal
    /// A personal tool with the name of a team one: it wins.
    public var overridesTeam = false
    public var id: String { name }

    public init(name: String, desc: String = "", method: Method, pkg: String? = nil, bin: String? = nil,
                install: String? = nil, update: String? = nil, requires: [String] = []) {
        self.name = name; self.desc = desc; self.method = method; self.pkg = pkg ?? name
        self.bin = bin ?? (method == .script ? name : method == .go ? (pkg ?? name).split(separator: "/").last.map(String.init) : nil)
        self.install = install; self.update = update; self.requires = requires
    }

    /// The name the package manager lists it under: a tap or a version pin is not part of it.
    public var key: String {
        switch method {
        case .brew, .cask: return pkg.split(separator: "/").last.map(String.init) ?? pkg
        case .uv, .pipx: return String(pkg.prefix { !"[=<>~!@; ".contains($0) })
        // pip lists a name in lower case with dashes, whatever the entry wrote.
        case .pip: return String(pkg.prefix { !"[=<>~!@; ".contains($0) }).lowercased().replacingOccurrences(of: "_", with: "-")
        // A scope starts with @; a version follows a later one.
        case .npm: return pkg.dropFirst().firstIndex(of: "@").map { String(pkg[..<$0]) } ?? pkg
        case .cargo, .go, .script: return method == .script ? name : pkg
        }
    }

    public var installLine: String {
        switch method {
        case .brew: "brew install " + Registry.shellQuote(pkg)
        case .cask: "brew install --cask " + Registry.shellQuote(pkg)
        case .uv: "uv tool install " + Registry.shellQuote(pkg)
        case .pipx: "pipx install " + Registry.shellQuote(pkg)
        case .pip: "python3 -m pip install --user " + Registry.shellQuote(pkg)
        case .npm: "npm install -g " + Registry.shellQuote(pkg)
        case .cargo: "cargo install " + Registry.shellQuote(pkg)
        case .go: "go install " + Registry.shellQuote(pkg.contains("@") ? pkg : pkg + "@latest")
        case .script: install ?? ""
        }
    }

    public var updateLine: String {
        switch method {
        case .brew: "brew upgrade " + Registry.shellQuote(pkg)
        case .cask: "brew upgrade --cask --greedy " + Registry.shellQuote(pkg)
        case .uv: "uv tool upgrade " + Registry.shellQuote(key)
        case .pipx: "pipx upgrade " + Registry.shellQuote(key)
        case .pip: "python3 -m pip install --user --upgrade " + Registry.shellQuote(pkg)
        case .npm: "npm install -g " + Registry.shellQuote(key + "@latest")
        case .cargo, .go: installLine
        case .script: update ?? install ?? ""
        }
    }

    /// Whether an update can be told apart from "nothing to do" before running it.
    public var knowsOutdated: Bool { method.knowsOutdated }
}

/// What this Mac has of one tool, as the last look found it.
public struct ToolStatus: Equatable, Sendable {
    public var installed = false
    public var version: String?
    /// Nil when nobody looked, or when the method cannot tell (a script).
    public var outdated: Bool?
    public var latest: String?
    /// Found on PATH but not through its package manager, so the manager cannot update it.
    public var elsewhere = false
    /// The package manager the method needs, when it is not on this Mac.
    public var managerMissing: String?

    public init(installed: Bool = false, version: String? = nil, outdated: Bool? = nil, latest: String? = nil,
                elsewhere: Bool = false, managerMissing: String? = nil) {
        self.installed = installed; self.version = version; self.outdated = outdated; self.latest = latest
        self.elsewhere = elsewhere; self.managerMissing = managerMissing
    }

    /// "installed 14.1.0", "update available 0.6.1 → 0.7.0", "missing".
    public var words: String {
        guard installed else { return managerMissing.map { "missing · needs \($0)" } ?? "missing" }
        if elsewhere { return "on PATH, not from its package manager" }
        if outdated == true { return "update available" + (version.map { " " + $0 } ?? "") + (latest.map { " → " + $0 } ?? "") }
        return "installed" + (version.map { " " + $0 } ?? "")
    }
}

extension Registry {
    public func tool(named name: String) -> Tool? { tools.first { $0.name == name } }
    public var teamTools: [Tool] { tools.filter { $0.origin == .team } }

    static func isValidPackage(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9@][A-Za-z0-9@._/+\\[\\]=<>~!,-]*$", options: .regularExpression) != nil
    }

    static func isValidProgram(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9][A-Za-z0-9._+-]*$", options: .regularExpression) != nil
    }

    /// `[[tool]]` entries as tools, or what is wrong with the first one that is not right.
    static func tools(from specs: [ToolSpec]) throws -> [Tool] {
        var out: [Tool] = []
        var seen: Set<String> = []
        let methods = Tool.Method.allCases.map(\.rawValue).joined(separator: ", ")
        for (i, spec) in specs.enumerated() {
            guard isValidName(spec.name) else {
                throw RegistryError("tool[\(i)]: '\(spec.name)' is not a valid name", fix: "lowercase letters, digits, . _ and -")
            }
            guard seen.insert(spec.name).inserted else {
                throw RegistryError("two tools are named \(spec.name)", fix: "one entry per tool")
            }
            guard let method = Tool.Method(rawValue: spec.method.trimmingCharacters(in: .whitespaces)) else {
                throw RegistryError("the tool \(spec.name): method '\(spec.method)' is not one of \(methods)", fix: "brew for a formula, cask for an app, uv for a Python tool, script for its own installer; great-gui tools methods lists them all")
            }
            let pkg = spec.pkg?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            if let pkg, !isValidPackage(pkg) {
                throw RegistryError("the tool \(spec.name): pkg '\(pkg)' is not a package name", fix: "what the package manager calls it, as in ripgrep or user/tap/name")
            }
            let bin = spec.bin?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            if let bin, !isValidProgram(bin) {
                throw RegistryError("the tool \(spec.name): bin '\(bin)' is not a program name", fix: "the program it puts on PATH, as in rg; no path and no arguments")
            }
            let install = spec.install?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let update = spec.update?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if method == .script {
                guard install != nil else {
                    throw RegistryError("the tool \(spec.name) has method script and no install", fix: "install is the shell line that installs it")
                }
                if pkg != nil { throw RegistryError("the tool \(spec.name): pkg is for the package managers", fix: "a script tool is found by bin; drop pkg") }
            } else if install != nil || update != nil {
                throw RegistryError("the tool \(spec.name): install and update are for method script", fix: "\(method.rawValue) derives its own lines; drop them, or use method = \"script\"")
            }
            let requires = spec.requires ?? []
            if let bad = requires.first(where: { !isValidProgram($0) }) {
                throw RegistryError("the tool \(spec.name): requires '\(bad)' is not a tool or program name", fix: "name another tool, or a program on PATH")
            }
            if requires.contains(spec.name) {
                throw RegistryError("the tool \(spec.name) requires itself", fix: "drop it from requires")
            }
            out.append(Tool(name: spec.name, desc: spec.desc ?? "", method: method, pkg: pkg, bin: bin, install: install, update: update, requires: requires))
        }
        return out
    }
}

struct ToolSpec: Decodable {
    var name: String
    var desc: String?
    var method: String
    var pkg: String?
    var bin: String?
    var install: String?
    var update: String?
    var requires: [String]?
    enum CodingKeys: String, CodingKey, CaseIterable { case name, desc, method, pkg, bin, install, update, requires }
}

/// Looking at what is installed, and the lines that install or update. Everything here is text in and text
/// out, so it is tested without a package manager; `ToolRunner` in the app runs it.
public enum ToolProbe {
    /// The places installers put programs, added behind the login shell's own PATH: an app started from the
    /// Dock has not read the files that usually add them.
    public static let pathLine = "export PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin\""

    /// One shell script that reports everything the status needs, in sections named by `@@` lines.
    /// - `versions`: also run each script tool's program with `--version`. The daily look leaves it off, so
    ///   nothing a registry names is executed unattended; it asks only the package managers and PATH.
    /// - `outdated`: also ask the package managers what is behind. Slow: Homebrew refreshes itself first.
    public static func script(for tools: [Tool], versions: Bool, outdated: Bool) -> String {
        let methods = Set(tools.map(\.method))
        var lines = [pathLine, "echo @@have"]
        for manager in Set(tools.compactMap(\.method.manager)).sorted() {
            lines.append("command -v \(manager) >/dev/null 2>&1 && echo \(manager)")
        }
        if methods.contains(.brew) { lines += ["echo @@brew", "brew list --formula --versions 2>/dev/null"] }
        if methods.contains(.cask) { lines += ["echo @@cask", "brew list --cask --versions 2>/dev/null"] }
        if methods.contains(.uv) { lines += ["echo @@uv", "uv tool list 2>/dev/null"] }
        if methods.contains(.pipx) { lines += ["echo @@pipx", "pipx list --short 2>/dev/null"] }
        if methods.contains(.pip) { lines += ["echo @@pip", "python3 -m pip list --user --format=freeze 2>/dev/null"] }
        if methods.contains(.npm) { lines += ["echo @@npm", "npm ls -g --depth=0 2>/dev/null"] }
        if methods.contains(.cargo) { lines += ["echo @@cargo", "cargo install --list 2>/dev/null"] }
        let bins = Array(Set(tools.compactMap(\.bin))).sorted()
        if !bins.isEmpty {
            lines.append("echo @@bin")
            lines.append("for b in " + bins.map(Registry.shellQuote).joined(separator: " ") + "; do command -v \"$b\" >/dev/null 2>&1 && echo \"$b\"; done")
        }
        if versions {
            lines.append("echo @@version")
            for t in tools where t.method == .script {
                guard let bin = t.bin else { continue }
                let b = Registry.shellQuote(bin)
                lines.append("command -v \(b) >/dev/null 2>&1 && echo \(Registry.shellQuote(t.name)) \"$(\(b) --version 2>&1 </dev/null | head -n 1)\"")
            }
        }
        if outdated {
            if methods.contains(.brew) || methods.contains(.cask) { lines.append("brew update --quiet >/dev/null 2>&1") }
            if methods.contains(.brew) { lines += ["echo @@brew-outdated", "brew outdated --formula --quiet 2>/dev/null"] }
            if methods.contains(.cask) { lines += ["echo @@cask-outdated", "brew outdated --cask --greedy --quiet 2>/dev/null"] }
            if methods.contains(.uv) { lines += ["echo @@uv-outdated", "uv tool list --outdated 2>/dev/null"] }
            if methods.contains(.npm) { lines += ["echo @@npm-outdated", "npm outdated -g --parseable 2>/dev/null"] }
        }
        lines.append("echo @@end")
        return lines.joined(separator: "\n")
    }

    static let versionPattern = try! NSRegularExpression(pattern: "[0-9]+(\\.[0-9]+)+[0-9A-Za-z.+-]*")

    static func version(in text: String) -> String? {
        guard let m = versionPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    /// The script's output as a status per tool name. Whatever the shell printed before the first section
    /// (a profile that greets) is ignored.
    public static func parse(_ output: String, tools: [Tool], outdated: Bool) -> [String: ToolStatus] {
        var sections: [String: [String]] = [:]
        var current: String?
        for raw in output.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("@@") { current = String(line.dropFirst(2)); sections[current!] = sections[current!] ?? []; continue }
            guard let current, !line.isEmpty else { continue }
            sections[current, default: []].append(line)
        }
        let have = Set(sections["have"] ?? [])
        let bins = Set(sections["bin"] ?? [])
        /// "name 1.2 1.3" lines: the name and its newest version.
        func listed(_ key: String) -> [String: String] {
            var out: [String: String] = [:]
            for line in sections[key] ?? [] {
                let words = line.split(separator: " ").map(String.init)
                guard let name = words.first else { continue }
                out[name] = words.count > 1 ? words[words.count - 1] : ""
            }
            return out
        }
        /// uv's "name v1.2.3 [latest: 1.3.0]" lines; the "- program" lines under each are skipped.
        func uvListed(_ key: String) -> [String: (version: String, latest: String?)] {
            var out: [String: (String, String?)] = [:]
            for line in sections[key] ?? [] where !line.hasPrefix("-") {
                let words = line.split(separator: " ").map(String.init)
                guard words.count >= 2 else { continue }
                let version = words[1].hasPrefix("v") ? String(words[1].dropFirst()) : words[1]
                var latest: String?
                if let r = line.range(of: "[latest: "), let end = line[r.upperBound...].firstIndex(of: "]") { latest = String(line[r.upperBound..<end]) }
                out[words[0]] = (version, latest)
            }
            return out
        }
        func names(_ key: String) -> Set<String> {
            Set((sections[key] ?? []).compactMap { $0.split(separator: " ").first?.split(separator: "/").last.map(String.init) })
        }
        /// "name@1.2.3" after whatever precedes it on the line: npm's tree, and its outdated fields.
        func at(_ word: String) -> (name: String, version: String)? {
            guard let i = word.dropFirst().lastIndex(of: "@") else { return nil }
            return (String(word[..<i]), String(word[word.index(after: i)...]))
        }
        var simple: [Tool.Method: [String: String]] = [.pipx: listed("pipx")]
        simple[.pip] = (sections["pip"] ?? []).reduce(into: [:]) { out, line in
            let parts = line.components(separatedBy: "==")
            if parts.count == 2 { out[parts[0].lowercased().replacingOccurrences(of: "_", with: "-")] = parts[1] }
        }
        simple[.npm] = (sections["npm"] ?? []).reduce(into: [:]) { out, line in
            // "+-- name@1.2.3", and a linked one adds "-> path": the name is the word after the branch.
            let words = line.split(separator: " ")
            if words.count >= 2, let found = at(String(words[1])) { out[found.name] = found.version }
        }
        // cargo: "name v1.2.3:" starts a block; the programs under it are indented, and trimmed here, so the colon tells.
        simple[.cargo] = (sections["cargo"] ?? []).reduce(into: [:]) { out, line in
            let words = line.split(separator: " ").map(String.init)
            if words.count >= 2, line.hasSuffix(":") { out[words[0]] = words[1].trimmingCharacters(in: CharacterSet(charactersIn: "v:")) }
        }
        // npm outdated --parseable: path:wanted:current:latest, each name@version.
        var npmBehind: [String: String] = [:]
        for line in sections["npm-outdated"] ?? [] {
            let fields = line.components(separatedBy: ":")
            if fields.count >= 4, let latest = at(fields[3]) { npmBehind[latest.name] = latest.version }
        }
        let brew = listed("brew"), cask = listed("cask"), uv = uvListed("uv"), uvBehind = uvListed("uv-outdated")
        let brewBehind = names("brew-outdated"), caskBehind = names("cask-outdated")
        var versions: [String: String] = [:]
        for line in sections["version"] ?? [] {
            guard let space = line.firstIndex(of: " ") else { continue }
            if let v = version(in: String(line[line.index(after: space)...])) { versions[String(line[..<space])] = v }
        }
        var out: [String: ToolStatus] = [:]
        for t in tools {
            var s = ToolStatus()
            switch t.method {
            case .brew, .cask:
                let list = t.method == .brew ? brew : cask
                if let v = list[t.key] {
                    s.installed = true
                    s.version = v.nilIfEmpty
                    if outdated { s.outdated = (t.method == .brew ? brewBehind : caskBehind).contains(t.key) }
                }
            case .uv:
                if let found = uv[t.key] {
                    s.installed = true
                    s.version = found.version
                    if outdated {
                        s.outdated = uvBehind[t.key] != nil
                        s.latest = uvBehind[t.key]?.latest
                    }
                }
            case .pipx, .pip, .npm, .cargo:
                if let v = simple[t.method]?[t.key] {
                    s.installed = true
                    s.version = v.nilIfEmpty
                    if outdated, t.method == .npm {
                        s.outdated = npmBehind[t.key] != nil
                        s.latest = npmBehind[t.key]
                    }
                }
            case .script, .go:
                if let bin = t.bin, bins.contains(bin) {
                    s.installed = true
                    s.version = versions[t.name]
                } else if let manager = t.method.manager, !have.contains(manager) {
                    s.managerMissing = manager
                }
            }
            if !s.installed, t.method.lists {
                if let bin = t.bin, bins.contains(bin) {
                    s.installed = true
                    s.elsewhere = true
                } else if let manager = t.method.manager, !have.contains(manager) {
                    s.managerMissing = manager
                }
            }
            out[t.name] = s
        }
        return out
    }

    /// The tools in an order that puts each after the ones it requires, as far as they are in the list.
    public static func ordered(_ tools: [Tool]) -> [Tool] {
        var out: [Tool] = []
        var placed: Set<String> = []
        var rest = tools
        while !rest.isEmpty {
            let names = Set(rest.map(\.name))
            let ready = rest.filter { t in t.requires.allSatisfy { placed.contains($0) || !names.contains($0) } }
            let next = ready.isEmpty ? [rest[0]] : ready   // a cycle: take them as written rather than loop
            for t in next { out.append(t); placed.insert(t.name) }
            rest.removeAll { placed.contains($0.name) }
        }
        return out
    }

    /// The shell lines that install or update one tool: PATH, a check that what it needs is there, then the
    /// line itself. `all` is the registry's tools, so a requirement that names one is found by its program.
    public static func runLine(_ tool: Tool, update: Bool, among all: [Tool]) -> String {
        var lines = [pathLine]
        func need(_ program: String, _ fix: String) {
            let message = "✗ \(tool.name) needs \(program), which is not installed" + (fix.isEmpty ? "" : " · " + fix)
            lines.append("command -v \(Registry.shellQuote(program)) >/dev/null 2>&1 || { echo \(Registry.shellQuote(message)) >&2; exit 127; }")
        }
        if let manager = tool.method.manager {
            let fix = manager == "brew" ? "Homebrew: https://brew.sh" : all.contains { $0.name == manager } ? "great-gui tools install \(manager)" : "install \(manager) first, or list it as a tool"
            need(manager, fix)
        }
        for r in tool.requires where r != tool.method.manager {
            let other = all.first { $0.name == r }
            need(other?.bin ?? r, other == nil ? "" : "great-gui tools install \(r)")
        }
        lines.append(update ? tool.updateLine : tool.installLine)
        return lines.joined(separator: "\n")
    }

    /// Several tools as one script, for a run the window shows: each announced, a failure counted and the
    /// rest still tried, and the exit code says whether all of them worked.
    public static func batch(_ picked: [(tool: Tool, update: Bool)], among all: [Tool]) -> String {
        var lines = ["fail=0"]
        for (tool, update) in picked {
            let line = update ? tool.updateLine : tool.installLine
            lines.append("echo " + Registry.shellQuote("→ \(update ? "update" : "install") \(tool.name) · \(line.components(separatedBy: "\n")[0])"))
            lines.append("(\n" + runLine(tool, update: update, among: all) + "\n) && echo " + Registry.shellQuote("✓ \(tool.name)")
                + " || { echo " + Registry.shellQuote("✗ \(tool.name) failed") + "; fail=1; }")
            lines.append("echo")
        }
        lines.append("exit $fail")
        return lines.joined(separator: "\n")
    }
}
