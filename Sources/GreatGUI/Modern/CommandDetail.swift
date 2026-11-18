import Registry
import SwiftUI
import TerminalDesign

/// One command: what it is, Run, Stop and Edit beside its name, what it runs, its parameters, and below
/// a row of tabs between the output, the embedded terminal, its history and, when scheduled, its log.
struct CommandDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let command: Command

    private var palette: Palette { Palette(scheme: scheme) }
    /// This command is running, or waiting on Touch ID or the Keychain.
    private var isBusy: Bool {
        guard let r = model.run, r.name == command.name else { return false }
        return r.status == .running || r.status == .gating || r.status == .unlocking
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                runLine
                if !command.params.isEmpty { parameters }
                if !command.env.isEmpty || command.envFile != nil || command.gate || command.cwd != nil || command.schedule != nil { facts }
                Tabs(palette: palette, values: tabs, selection: $model.detailTab) { $0.rawValue }
                switch model.detailTab {
                case .output: OutputLog(command: command, palette: palette)
                case .terminal: TerminalPanel(command: command, palette: palette)
                case .history: HistoryRows(rows: model.history(for: command.name), showName: false, palette: palette, gutter: 0)
                case .log: ScheduledLog(command: command, palette: palette)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: command.name, initial: true) { _, _ in
            model.detailTab = command.interactive ? .terminal : .output
        }
    }

    private var tabs: [AppModel.DetailTab] {
        command.schedule != nil ? AppModel.DetailTab.allCases : AppModel.DetailTab.allCases.filter { $0 != .log }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            palette.kicker(command.origin == .team ? "Team command" : command.overridesTeam ? "Your command · overrides the team's" : "Command")
            HStack(alignment: .center, spacing: 10) {
                Text(command.name).heading(palette).lineLimit(1)
                Spacer(minLength: 12)
                Button { model.runSelected() } label: { Label("Run", systemImage: "play.fill") }
                    .primaryButton(palette)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isBusy)
                    .help("Run \(command.name) (⌘↩)")
                Button { model.terminate() } label: { Label("Stop", systemImage: "stop.fill") }
                    .secondaryButton(palette)
                    .disabled(!isBusy || command.interactive)
                    .help("Stop the run (⌘.)")
                Button { model.openEditCommand(command) } label: {
                    Label(command.origin == .team ? "Copy" : "Edit", systemImage: command.origin == .team ? "plus.square.on.square" : "pencil")
                }
                .secondaryButton(palette)
                .help(command.origin == .team ? "Make your own copy of the team's \(command.name) (⌘E)" : "Edit \(command.name) (⌘E)")
            }
            HStack(spacing: 8) {
                // A team command's group pill would only repeat the "team" pill beside it.
                if !(command.origin == .team && command.group == "team") {
                    Text(command.group)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .pill(palette.tint.opacity(0.18), palette)
                }
                if let mark = palette.mark(for: command) {
                    Label(mark.text, systemImage: mark.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(mark.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .pill(mark.color.opacity(0.14), palette)
                }
                if command.origin == .team || command.overridesTeam {
                    Label(command.origin == .team ? "team" : "overrides team", systemImage: "person.2")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .pill(palette.muted.opacity(0.14), palette)
                }
                if !command.desc.isEmpty { Text(command.desc).foregroundStyle(palette.muted).lineLimit(2) }
            }
            if command.origin == .team {
                Text("From the team's registry, so it is read-only here. Copy makes your own, which wins over theirs."
                     + (command.teamSchedule.map { " The team suggests running it \($0.english); that is not armed until your copy has the schedule." } ?? ""))
                    .font(.callout).foregroundStyle(palette.muted)
            }
        }
    }

    private var runLine: some View {
        let preview = (try? model.registry?.resolve(command, params: model.paramValues, partial: true))?.run ?? command.run
        return VStack(alignment: .leading, spacing: 6) {
            Text("Runs").sectionLabel(palette)
            Text(preview)
                .font(Palette.mono)
                .foregroundStyle(palette.codeText)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .codeBlock(palette)
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parameters").sectionLabel(palette)
            ForEach(command.params, id: \.name) { p in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(p.name + (p.required ? " *" : "")).font(Palette.mono).frame(width: 130, alignment: .leading)
                    TextField(p.name, text: binding(p.name), prompt: Text(p.desc.isEmpty ? (p.defaultValue ?? "") : p.desc))
                        .font(Palette.mono)
                        .fieldBox(palette)
                        .onSubmit { model.runSelected() }
                }
            }
        }
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(get: { model.paramValues[name] ?? "" }, set: { model.paramValues[name] = $0 })
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let line = model.scheduleLine(for: command) {
                HStack(spacing: 10) {
                    Label { Text(line) } icon: { Image(systemName: model.isPaused(command.name) ? "pause.circle" : "clock") }
                        .foregroundStyle(model.isPaused(command.name) ? palette.warn : palette.muted)
                    Button(model.isPaused(command.name) ? "Resume" : "Pause") { model.togglePause(command.name) }.rowAction(palette)
                }
            }
            if let cwd = command.cwd {
                Label { Text(cwd).font(Palette.mono) } icon: { Image(systemName: "folder") }
            }
            ForEach(command.env.keys.sorted(), id: \.self) { k in
                let value = command.env[k]
                Label { Text("\(k) = \(value?.display ?? "")").font(Palette.mono) } icon: { Image(systemName: value?.isSecret == true ? "key.fill" : "equal.square") }
            }
            if let f = command.envFile {
                Label { Text("env file = \(EnvValue.keychainPrefix)\(f)").font(Palette.mono) } icon: { Image(systemName: "doc.badge.gearshape") }
                    .help("A whole .env from the Keychain: its entries join the environment; the file is never written to disk.")
            }
            if command.gate {
                Label("Touch ID or your password before every run", systemImage: "lock.fill").foregroundStyle(palette.warn)
            }
        }
        .font(.callout)
        .foregroundStyle(palette.muted)
    }
}

/// The run's lines in the design's mono type on the code ground, a live status chip, the exit footer.
private struct OutputLog: View {
    @Environment(AppModel.self) private var model
    let command: Command
    let palette: Palette

    var body: some View {
        if let run = model.run, run.name == command.name, !run.interactive {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusChip(run: run, palette: palette)
                    Spacer()
                    if case .done(let code, let seconds) = run.status {
                        Text("exit \(code) · \(seconds)s · \(run.lines.count) line\(run.lines.count == 1 ? "" : "s")"
                             + (run.redact.isEmpty ? "" : " · \(run.redact.count) secret\(run.redact.count == 1 ? "" : "s") redacted"))
                            .font(.caption).foregroundStyle(palette.muted)
                    }
                }
                if case .failed(let what, let fix) = run.status {
                    NoteLine(note: AppModel.Note(ok: false, text: what, fix: fix), palette: palette)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(run.lines.enumerated()), id: \.offset) { i, line in
                                    Text(line.isEmpty ? " " : line)
                                        .font(Palette.mono)
                                        .foregroundStyle(palette.codeText)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(i)
                                }
                            }
                            .padding(12)
                        }
                        .frame(minHeight: 180, maxHeight: 440)
                        .codeBlock(palette)
                        .onChange(of: run.lines.count) { _, n in
                            if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
                        }
                    }
                }
            }
        } else if command.interactive {
            quiet("Runs in the terminal", "This command needs a terminal; its output appears under Terminal.")
        } else {
            quiet("Not run yet", "⌘↩ runs it. Output appears here.")
        }
    }

    private func quiet(_ title: String, _ text: String) -> some View { QuietNote(title: title, text: text, palette: palette) }
}

/// A tab with nothing to show yet: two lines on the code ground, where the output will be.
struct QuietNote: View {
    let title: String
    let text: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(palette.title(16)).tracking(palette.tracking(16))
            Text(text).font(.callout).foregroundStyle(palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .codeBlock(palette)
    }
}

/// running · waiting · done · failed, as one chip in the theme. While a run is going, a band of the accent
/// colour moves across it.
struct StatusChip: View {
    let run: AppModel.RunState
    let palette: Palette

    var body: some View {
        HStack(spacing: 6) {
            switch run.status {
            case .running:
                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(palette.accent)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("running · \(max(0, Int(ctx.date.timeIntervalSince(run.startedAt))))s")
                }
            case .gating:
                Image(systemName: "touchid").foregroundStyle(palette.warn)
                Text("Touch ID or your password")
            case .unlocking:
                Image(systemName: "key.fill").foregroundStyle(palette.warn)
                Text("reading the Keychain")
            case .done(let code, _):
                Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(code == 0 ? palette.ok : palette.err)
                Text(code == 0 ? "done" : "exit \(code)")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.err)
                Text("did not run")
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background { if run.status == .running { Sweep(color: palette.accent.opacity(0.22)) } }
        .chip(palette)
        .clipShape(RoundedRectangle(cornerRadius: palette.paper ? 0 : 14, style: .continuous))
    }
}

/// A band that crosses its container again and again: the chip's sign that something is running.
private struct Sweep: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            GeometryReader { g in
                let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                let band = g.size.width * 0.45
                Rectangle().fill(color).frame(width: band).offset(x: (g.size.width + band) * phase - band)
            }
        }
    }
}

/// The embedded terminal for an interactive command, on the code ground.
private struct TerminalPanel: View {
    @Environment(AppModel.self) private var model
    let command: Command
    let palette: Palette

    var body: some View {
        if let run = model.run, run.name == command.name, run.interactive, run.status == .running || run.isDone {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusChip(run: run, palette: palette)
                    Spacer()
                    Text(run.isDone ? "the shell has ended" : "ctrl-d leaves").font(.caption).foregroundStyle(palette.muted)
                }
                TerminalPane(run: run, theme: palette.theme) { code in model.finishInteractive(code: code) }
                    .frame(height: 24 * TermFont.line + 16)
                    .padding(8)
                    .codeBlock(palette)
            }
        } else if let run = model.run, run.name == command.name, run.interactive, run.status == .unlocking || run.status == .gating {
            StatusChip(run: run, palette: palette)
        } else if let run = model.run, run.name == command.name, case .failed(let what, let fix) = run.status {
            NoteLine(note: AppModel.Note(ok: false, text: what, fix: fix), palette: palette)
        } else if command.interactive {
            QuietNote(title: "Not run yet", text: "⌘↩ opens this command in a terminal here.", palette: palette)
        } else {
            QuietNote(title: "Not a terminal command", text: "Turn on Needs a terminal in its form (⌘E) for a program that needs one.", palette: palette)
        }
    }
}

/// Runs as rows in the theme: when, how, the exit code, how long, and the line that ran; the command's
/// name too when the rows span every command.
struct HistoryRows: View {
    let rows: [HistoryEntry]
    let showName: Bool
    let palette: Palette
    /// The screen's side gutter; 0 inside the command detail, which has its own padding.
    var gutter: CGFloat = 24

    var body: some View {
        if rows.isEmpty {
            QuietNote(title: "No runs yet", text: "Every run is recorded here.", palette: palette).padding(gutter)
        } else {
            VStack(spacing: 0) {
                HeaderRow(palette: palette, columns: [("When", 96)] + (showName ? [("Command", 190)] : []) + [("How", 84), ("Exit", 46), ("Took", 56), ("Ran", nil)])
                    .padding(.horizontal, gutter - 24)
                ForEach(rows) { h in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(HistoryStore.relative(h.startedAt)).foregroundStyle(palette.muted).cell(96)
                        if showName { Text(h.name).font(Palette.mono).lineLimit(1).cell(190) }
                        Text(HistoryStore.modeName(h.mode)).foregroundStyle(palette.muted).cell(84)
                        Text("\(h.code)").font(Palette.mono).foregroundStyle(h.code == 0 ? palette.ok : palette.err).cell(46)
                        Text(String(format: "%.1fs", h.seconds)).foregroundStyle(palette.muted).cell(56)
                        Text(h.run).font(Palette.mono).lineLimit(1).truncationMode(.tail).help(h.run).cell(nil)
                    }
                    .font(.callout)
                    .tableRow(palette)
                    .padding(.horizontal, gutter - 24)
                }
            }
        }
    }
}

/// The last scheduled run's output, read from the command's log file.
private struct ScheduledLog: View {
    @Environment(AppModel.self) private var model
    let command: Command
    let palette: Palette

    var body: some View {
        if let text = model.lastLog(of: command.name) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last scheduled run").sectionLabel(palette)
                    Spacer()
                    Button("Reveal log") { model.revealLog(of: command.name) }.rowAction(palette)
                }
                ScrollView {
                    Text(text)
                        .font(Palette.mono)
                        .foregroundStyle(palette.codeText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 200, maxHeight: 420)
                .codeBlock(palette)
            }
        } else {
            QuietNote(title: "No scheduled run yet",
                      text: command.schedule.map { "launchd runs it \($0.english); the output lands here." } ?? "This command has no schedule.", palette: palette)
        }
    }
}
