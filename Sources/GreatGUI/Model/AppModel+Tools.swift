import Foundation
import Registry

/// The tools the registry lists (DECISIONS local-028): what this Mac has of each, and the runs that install
/// or update them. A look asks the package managers and PATH; nothing is installed until a button is pressed.
extension AppModel {
    static let toolsRunName = "tools"

    var tools: [Tool] { registry?.tools ?? [] }
    var toolsMissing: [Tool] { tools.filter { toolStatus[$0.name].map { !$0.installed } ?? false } }
    var toolsOutdated: [Tool] { tools.filter { toolStatus[$0.name]?.outdated == true } }
    /// How many want something done: the sidebar's badge.
    var toolsAttention: Int { toolsMissing.count + toolsOutdated.count }
    var toolsRunning: Bool { run?.name == Self.toolsRunName && run?.status == .running }

    /// "5 tools · 1 missing · 2 updates · checked 3h ago"
    var toolsSummary: String {
        if toolsBusy, toolStatus.isEmpty { return "looking…" }
        var parts = ["\(tools.count) tool\(tools.count == 1 ? "" : "s")"]
        if !toolsMissing.isEmpty { parts.append("\(toolsMissing.count) missing") }
        if !toolsOutdated.isEmpty { parts.append("\(toolsOutdated.count) update\(toolsOutdated.count == 1 ? "" : "s")") }
        if toolsBusy { parts.append("looking…") }
        else if let at = toolsCheckedAt { parts.append("checked for updates " + HistoryStore.relative(at)) }
        else { parts.append("not checked for updates yet") }
        return parts.joined(separator: " · ")
    }

    /// Looks, in the background. `outdated` also asks what is behind (slow: Homebrew refreshes first).
    /// `versions` runs each script tool's own `--version`; the daily look passes false, so it executes
    /// nothing a registry names.
    func refreshTools(outdated: Bool = false, versions: Bool = true) {
        let tools = self.tools
        guard !tools.isEmpty else { toolStatus = [:]; return }
        guard !toolsBusy else { return }
        toolsBusy = true
        if outdated { toolsCheckedAt = Date() }
        Task.detached(priority: .utility) { [weak self] in
            let status = ToolRunner.status(tools, versions: versions, outdated: outdated)
            await self?.finishToolsLook(status, outdated: outdated)
        }
    }

    private func finishToolsLook(_ status: [String: ToolStatus], outdated: Bool) {
        toolsBusy = false
        // A look that did not ask what is behind keeps what the last one that did had found.
        toolStatus = status.reduce(into: [:]) { out, pair in
            var s = pair.value
            if !outdated, s.installed, let old = toolStatus[pair.key], old.installed, old.version == nil || s.version == nil || old.version == s.version {
                s.outdated = old.outdated
                s.latest = old.latest
                if s.version == nil { s.version = old.version }
            }
            out[pair.key] = s
        }
    }

    /// Installs the named tools, or every missing one.
    func installTools(_ names: [String]? = nil) {
        let picked = names.map { n in tools.filter { n.contains($0.name) } } ?? toolsMissing
        runTools(picked.map { ($0, false) }, verb: "install")
    }

    /// Updates the named tools, or every one a package manager says is behind.
    func updateTools(_ names: [String]? = nil) {
        let picked = names.map { n in tools.filter { n.contains($0.name) } } ?? toolsOutdated
        runTools(picked.map { ($0, true) }, verb: "update")
    }

    /// One run in an embedded terminal, so an installer that asks for a password can be answered.
    private func runTools(_ picked: [(tool: Tool, update: Bool)], verb: String) {
        guard !picked.isEmpty else { return }
        if let r = run, r.status == .running {
            refuse("\(r.name) is running", fix: "let it finish or stop it (⌘.) first")
            return
        }
        let ordered = ToolProbe.ordered(picked.map(\.tool)).map { t in (tool: t, update: picked.first { $0.tool.name == t.name }?.update ?? false) }
        toolsRunSummary = verb + " " + ordered.map(\.tool.name).joined(separator: ", ")
        clearRegistryNote()
        startAsIs(name: Self.toolsRunName, run: ToolProbe.batch(ordered, among: tools), interactive: true)
        toolRunOpen = true
    }

    // MARK: adding and removing an entry (the person's own file only)

    func openToolForm() {
        toolDraft = ToolDraft()
        toolNote = nil
        toolSheetOpen = true
    }

    /// Writes the draft as a `[[tool]]` block in the person's file. Nothing is installed.
    @discardableResult
    func saveTool() -> Bool {
        do {
            let d = toolDraft
            let script = d.method == "script"
            let tool = try RegistryWriter.buildTool(name: d.name, method: d.method.trimmingCharacters(in: .whitespaces), desc: d.desc,
                                                    pkg: script ? "" : d.pkg.trimmingCharacters(in: .whitespaces), bin: d.bin.trimmingCharacters(in: .whitespaces),
                                                    install: script ? d.install : "", update: script ? d.update : "",
                                                    requires: RegistryWriter.parseTags(d.requires))
            _ = try RegistryWriter.appendTool(tool, to: registryURL)
            let committed = RegistryWriter.autoCommit(registryURL, message: "add tool \(tool.name)")
            reload()
            refreshTools()
            toolDraft = ToolDraft()
            toolSheetOpen = false
            toolNote = Note(ok: true, text: "\(tool.name) listed" + (committed ? " · committed" : "") + " · not installed yet: Install runs  \(tool.installLine.components(separatedBy: "\n")[0])")
            return true
        } catch let e as RegistryError {
            toolNote = Note(ok: false, text: e.what, fix: e.fix)
        } catch {
            toolNote = Note(ok: false, text: "\(error)")
        }
        return false
    }

    /// Drops the entry from the person's file. Nothing is uninstalled; a team tool is not theirs to drop.
    func removeTool(_ name: String) {
        guard let tool = registry?.tool(named: name) else { return }
        guard tool.origin == .personal else {
            toolNote = Note(ok: false, text: "\(name) is the team's and is read-only here", fix: "it is only a listing: nothing installs unless you ask")
            return
        }
        do {
            _ = try RegistryWriter.removeTool(name, from: registryURL)
            let committed = RegistryWriter.autoCommit(registryURL, message: "remove tool \(name)")
            reload()
            refreshTools()
            toolNote = Note(ok: true, text: "\(name) is off the list" + (committed ? " · committed" : "") + " · nothing was uninstalled")
        } catch let e as RegistryError {
            toolNote = Note(ok: false, text: e.what, fix: e.fix)
        } catch {
            toolNote = Note(ok: false, text: "\(error)")
        }
    }

    func closeToolRun() {
        toolRunOpen = false
        if let r = run, r.name == Self.toolsRunName, r.status != .running { dismissRun() }
    }
}
