import Foundation
import Registry

/// `great-gui tools …`: the programs the registry says this Mac should have (DECISIONS local-028). Looking
/// asks the package managers and PATH; install and update run only here, when asked, never by a sync.
extension CLI {
    static let toolsUsage = "great-gui tools [--check] · tools install [NAME]… · tools update [NAME]… · tools add NAME --method METHOD · tools remove NAME · tools methods"

    static func tools(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        let rest = Array(args.dropFirst())
        do {
            switch args.first {
            case nil, "list", "status": return try toolsStatus(args)
            case "--check": return try toolsStatus(args)
            case "install": return try toolsRun(rest, update: false)
            case "update", "upgrade": return try toolsRun(rest, update: true)
            case "add": return try toolsAdd(rest)
            case "methods": return toolsMethods()
            case "remove", "rm": return try toolsRemove(rest)
            default:
                fail("unknown tools command \(args[0])", fix: toolsUsage)
                return 2
            }
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    /// A tool as data: what it is, whose, the exact lines an install or update would run, and what this Mac has.
    static func describe(_ t: Tool, _ s: ToolStatus?) -> [String: Any] {
        var d: [String: Any] = ["name": t.name, "desc": t.desc, "method": t.method.rawValue, "origin": t.origin.rawValue,
                                "requires": t.requires, "install": t.installLine, "update": t.updateLine]
        if t.method != .script { d["pkg"] = t.pkg }
        if let bin = t.bin { d["bin"] = bin }
        if t.overridesTeam { d["overrides_team"] = true }
        if let s {
            d["installed"] = s.installed
            d["status"] = s.words
            if let v = s.version { d["version"] = v }
            if let o = s.outdated { d["outdated"] = o }
            if let l = s.latest { d["latest"] = l }
            if s.elsewhere { d["elsewhere"] = true }
            if let m = s.managerMissing { d["needs"] = m }
        }
        return d
    }

    /// What is installed, and with `--check` what is behind. Exit 1 when a listed tool is missing.
    static func toolsStatus(_ args: [String]) throws -> Int32 {
        let flags = args.filter { $0 != "list" && $0 != "status" }
        if let bad = flags.first(where: { $0 != "--check" }) { fail("unknown argument \(bad)", fix: toolsUsage); return 2 }
        let check = flags.contains("--check")
        let reg = try Registry.loadAll()
        let status = ToolRunner.status(reg.tools, versions: true, outdated: check)
        let missing = reg.tools.filter { status[$0.name]?.installed != true }.map(\.name)
        let behind = reg.tools.filter { status[$0.name]?.outdated == true }.map(\.name)
        if json {
            emit(["ok": missing.isEmpty, "tools": reg.tools.map { describe($0, status[$0.name]) }, "missing": missing, "outdated": behind, "checked_for_updates": check])
            return missing.isEmpty ? 0 : 1
        }
        guard !reg.tools.isEmpty else {
            print("✓ no tools listed · great-gui tools add NAME --method brew|cask|uv|pipx|pip|npm|cargo|go|script, or a [[tool]] entry in \(reg.url.lastPathComponent)")
            return 0
        }
        var facts = [count(reg.tools.count, "tool")]
        if !missing.isEmpty { facts.append("\(missing.count) missing") }
        if check { facts.append(behind.isEmpty ? "none behind" : count(behind.count, "update") + " available") }
        print((missing.isEmpty ? "✓ " : "▲ ") + facts.joined(separator: " · "))
        for t in reg.tools {
            let words = status[t.name]?.words ?? "unknown"
            print("    " + t.name.padding(toLength: 20, withPad: " ", startingAt: 0) + words.padding(toLength: 36, withPad: " ", startingAt: 0)
                + t.method.rawValue + (t.origin == .team ? " · team" : "") + (t.desc.isEmpty ? "" : "  " + t.desc))
        }
        if !missing.isEmpty { print("  install what is missing: great-gui tools install") }
        if !behind.isEmpty { print("  update what is behind: great-gui tools update") }
        if !check { print("  --check also asks the package managers what is behind") }
        return missing.isEmpty ? 0 : 1
    }

    /// Installs or updates, one tool at a time in this terminal, each recorded in the history. With no names:
    /// install takes what is missing; update takes what the package managers say is behind, and the script
    /// tools that carry an update line of their own.
    static func toolsRun(_ args: [String], update: Bool) throws -> Int32 {
        let verb = update ? "update" : "install"
        if let flag = args.first(where: { $0.hasPrefix("-") }) { fail("unknown flag \(flag)", fix: "great-gui tools \(verb) [NAME]…"); return 2 }
        let reg = try Registry.loadAll()
        var picked: [Tool] = []
        for name in args {
            guard let t = reg.tool(named: name) else { fail("no tool named \(name)", fix: "great-gui tools lists them"); return 2 }
            if !picked.contains(t) { picked.append(t) }
        }
        let status = ToolRunner.status(reg.tools, versions: false, outdated: update && args.isEmpty)
        var skipped: [[String: Any]] = []
        func skip(_ t: Tool, _ why: String) {
            skipped.append(["name": t.name, "reason": why])
            if !json { print("✓ \(t.name) · \(why)") }
        }
        if args.isEmpty {
            picked = reg.tools.filter { t in
                guard let s = status[t.name] else { return false }
                if !update { return !s.installed }
                return s.installed && !s.elsewhere && (s.outdated == true || (t.method == .script && t.update != nil))
            }
        } else {
            picked = picked.filter { t in
                let s = status[t.name] ?? ToolStatus()
                if !update, s.installed { skip(t, "already installed"); return false }
                if update, !s.installed { skip(t, "not installed: great-gui tools install \(t.name)"); return false }
                if update, s.elsewhere { skip(t, "on PATH but not from \(t.method.manager ?? "its installer"), so it is not this app's to update"); return false }
                return true
            }
        }
        picked = ToolProbe.ordered(picked)
        var results: [[String: Any]] = []
        var failed: [String] = []
        for t in picked {
            let line = update ? t.updateLine : t.installLine
            if !json { print("→ \(verb) \(t.name) · \(line.components(separatedBy: "\n")[0])") }
            var script = ToolProbe.runLine(t, update: update, among: reg.tools)
            // An agent reads one JSON object on stdout: the installer's own output goes to stderr.
            if json { script = "(\n" + script + "\n) 1>&2" }
            // Our own lines are buffered when stdout is a pipe: out they go before the installer writes.
            fflush(stdout)
            let started = Date()
            let code: Int32
            do {
                code = try runMasked(shellArguments: ["-lc", script], cwd: nil, environment: ProcessInfo.processInfo.environment, redact: [])
            } catch {
                fail("could not start the shell: \(error.localizedDescription)")
                return 2
            }
            let seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
            HistoryStore().append(HistoryEntry(name: "tools", run: "\(verb) \(t.name): \(line)", cwd: nil, mode: "cli", code: code, seconds: seconds, startedAt: started))
            results.append(["name": t.name, "action": verb, "code": Int(code), "seconds": seconds, "line": line])
            if code != 0 { failed.append(t.name) }
            if !json { print(code == 0 ? "✓ \(t.name) · \(seconds)s" : "✗ \(t.name) · exit \(code)") }
        }
        if json {
            emit(["ok": failed.isEmpty, "action": verb, "results": results, "skipped": skipped, "failed": failed])
        } else if picked.isEmpty, skipped.isEmpty {
            print(update ? "✓ nothing to update" : "✓ nothing is missing")
        } else if !failed.isEmpty {
            fail("\(failed.joined(separator: ", ")) did not \(verb)", fix: "the output above says why; great-gui tools shows where things stand")
        }
        return failed.isEmpty ? 0 : 1
    }

    /// Every install method and the lines it derives, so nobody has to guess what an entry will run.
    static func toolsMethods() -> Int32 {
        let rows = Tool.Method.allCases.map { m -> (Tool.Method, Tool) in
            (m, Tool(name: "NAME", method: m, pkg: m == .script ? nil : "PKG", bin: m == .go || m == .script ? "BIN" : nil, install: m == .script ? "the install line you give" : nil))
        }
        if json {
            emit(["ok": true, "methods": rows.map { m, t in
                ["method": m.rawValue, "means": m.words, "needs": m.manager ?? "", "install": t.installLine, "update": t.updateLine,
                 "found_by": m.lists ? "the manager's own list" : "bin on PATH", "knows_outdated": m.knowsOutdated] as [String: Any]
            }])
            return 0
        }
        for (m, t) in rows {
            print("◆ " + m.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0) + m.words)
            print("    install  " + t.installLine)
            if m != .script { print("    update   " + t.updateLine) }
            print("    found by " + (m.lists ? "\(m.manager ?? "")'s own list" : "bin on PATH") + (m.knowsOutdated ? " · can say when it is behind" : " · cannot say when it is behind: update it by name"))
        }
        return 0
    }

    static func toolsAdd(_ args: [String]) throws -> Int32 {
        let usage = "great-gui tools add NAME --method brew|cask|uv|pipx|pip|npm|cargo|go|script [--pkg P] [--bin B] [--desc …] [--install \"…\"] [--update \"…\"] [--requires R]…"
        var name: String?, values: [String: String] = [:], requires: [String] = [], commit = true
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--method", "--pkg", "--bin", "--desc", "--description", "--install", "--update", "--requires":
                guard i + 1 < args.count else { fail("\(a) needs a value", fix: usage); return 2 }
                i += 1
                let key = a == "--description" ? "--desc" : a
                if key == "--requires" {
                    requires += RegistryWriter.parseTags(args[i])
                } else {
                    values[key] = args[i]
                }
            case "--no-commit": commit = false
            default:
                if a.hasPrefix("-") { fail("unknown flag \(a)", fix: usage); return 2 }
                if name == nil { name = a } else { fail("one name only; \(a) is extra", fix: usage); return 2 }
            }
            i += 1
        }
        guard let name, let method = values["--method"] else { fail("tools add needs a name and --method", fix: usage); return 2 }
        let tool = try RegistryWriter.buildTool(name: name, method: method, desc: values["--desc"] ?? "", pkg: values["--pkg"] ?? "", bin: values["--bin"] ?? "",
                                                install: values["--install"] ?? "", update: values["--update"] ?? "", requires: requires)
        let url = Registry.defaultURL()
        let registry = try RegistryWriter.appendTool(tool, to: url)
        var facts = [tool.method.rawValue, count(registry.tools.count, "tool")]
        if commit, RegistryWriter.autoCommit(url, message: "add tool \(tool.name)") { facts.append("committed") }
        if json { emit(["ok": true, "tool": describe(tool, nil)]); return 0 }
        print("✓ added the tool \(tool.name) · " + facts.joined(separator: " · "))
        print("  nothing was installed: great-gui tools install \(tool.name) runs  \(tool.installLine.components(separatedBy: "\n")[0])")
        return 0
    }

    static func toolsRemove(_ args: [String]) throws -> Int32 {
        let commit = !args.contains("--no-commit")
        let names = args.filter { $0 != "--no-commit" }
        if let flag = names.first(where: { $0.hasPrefix("-") }) { fail("unknown flag \(flag)", fix: "great-gui tools remove NAME"); return 2 }
        guard names.count == 1 else { fail("tools remove needs one name", fix: "great-gui tools remove NAME"); return 2 }
        let name = names[0], url = Registry.defaultURL()
        if try Registry.load(from: url).tool(named: name) == nil, (try? Registry.loadAll())?.tool(named: name)?.origin == .team {
            fail("\(name) is the team's and is read-only here", fix: "it is only a listing: nothing installs unless you ask")
            return 2
        }
        let registry = try RegistryWriter.removeTool(name, from: url)
        var facts = [count(registry.tools.count, "tool")]
        if commit, RegistryWriter.autoCommit(url, message: "remove tool \(name)") { facts.append("committed") }
        if json { emit(["ok": true, "removed": name]); return 0 }
        print("✓ removed the tool \(name) from the registry · " + facts.joined(separator: " · ") + " · nothing was uninstalled")
        return 0
    }
}
