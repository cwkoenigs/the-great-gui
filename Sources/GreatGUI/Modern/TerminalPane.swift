import AppKit
import Registry
import Runner
import SwiftTerm
import SwiftUI
import TerminalDesign

/// An interactive run: SwiftTerm's local-process terminal, drawn in the design's colours, running the
/// command in an interactive login shell so aliases and PATH are yours.
struct TerminalPane: NSViewRepresentable {
    let run: AppModel.RunState
    let theme: TermTheme
    let onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        makeTerminal(coordinator: context.coordinator)
    }

    func makeTerminal(coordinator: Coordinator, initialSize: NSSize? = nil) -> LocalProcessTerminalView {
        let view = MountedTerminalView(frame: NSRect(origin: .zero, size: initialSize ?? .zero))
        view.processDelegate = coordinator
        view.font = TermFont.nsFont()
        Self.apply(theme, to: view)
        var env = ProcessInfo.processInfo.environment
        env.merge(run.env) { _, new in new }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let shell = ProcessRun.defaultShell()
        let launch: (LocalProcessTerminalView) -> Void = { [run] terminal in
            terminal.startProcess(executable: shell, args: ["-lic", run.run],
                                  environment: env.map { "\($0.key)=\($0.value)" }, currentDirectory: run.cwd)
            // The split view's lists may hold the keyboard a beat longer.
            for delay in [0.0, 0.15, 0.4] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak terminal] in
                    guard let terminal else { return }
                    terminal.window?.makeFirstResponder(terminal)
                }
            }
        }
        if initialSize != nil { launch(view) }
        else { view.launch = launch }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        Self.apply(theme, to: view)
    }

    static func apply(_ t: TermTheme, to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(t.bg)
        view.nativeForegroundColor = NSColor(t.text)
        view.caretColor = NSColor(t.cursorBg)
        view.selectedTextBackgroundColor = NSColor(t.hl)
        view.installColors(ansi(t))
    }

    /// The 16 ANSI colours from the roles: outcomes keep their meaning, blues are the brand and accent.
    static func ansi(_ t: TermTheme) -> [SwiftTerm.Color] {
        let roles: [Tokens.Role] = [.bg, .err, .ok, .warn, .brand, .accent, .accent, .text,
                                    .dim, .err, .ok, .warn, .brand, .strong, .strong, .text]
        return roles.map { role in
            let c = TermTheme.rgb8(t.hex(role))
            return SwiftTerm.Color(red8: c.r, green8: c.g, blue8: c.b)
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: (Int32?) -> Void
        init(onExit: @escaping (Int32?) -> Void) { self.onExit = onExit }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processFailedToStart(source: TerminalView, error: LocalProcessError) {
            DispatchQueue.main.async { [onExit] in onExit(nil) }
        }
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            source.requestRedraw()
            DispatchQueue.main.async { [onExit] in onExit(exitCode) }
        }
    }
}

/// Created by Run. The PTY, scrollback and exit delegate live together until the run is replaced.
@MainActor
final class CommandTerminalSession: NSObject {
    let terminal: LocalProcessTerminalView
    private let coordinator: TerminalPane.Coordinator

    init(run: AppModel.RunState, onExit: @escaping (Int32?) -> Void) {
        let pane = TerminalPane(run: run, theme: .dark, onExit: onExit)
        coordinator = pane.makeCoordinator()
        // A nonzero grid also preserves fast output before the first window is attached.
        let size = NSSize(width: 80 * TermFont.cellWidth, height: 24 * TermFont.line)
        terminal = pane.makeTerminal(coordinator: coordinator, initialSize: size)
    }
}

/// SwiftUI may create several presentations of the same run. Only the host that owns the
/// terminal accepts input. Another window can bring that same live terminal and its buffer here.
struct CommandTerminalPane: NSViewRepresentable {
    let session: CommandTerminalSession
    let theme: TermTheme

    func makeNSView(context: Context) -> Host { Host(frame: .zero) }

    func updateNSView(_ host: Host, context: Context) {
        host.display(session, theme: theme)
    }

    static func dismantleNSView(_ host: Host, coordinator: ()) {
        host.detach()
    }

    final class Host: NSView {
        private var session: CommandTerminalSession?
        private let showButton = NSButton(title: "Show Terminal Here", target: nil, action: nil)

        override init(frame: NSRect) {
            super.init(frame: frame)
            showButton.target = self
            showButton.action = #selector(attach)
            showButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(showButton)
            NSLayoutConstraint.activate([
                showButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                showButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { nil }

        func display(_ next: CommandTerminalSession, theme: TermTheme) {
            TerminalPane.apply(theme, to: next.terminal)
            guard session !== next else { return }
            detach()
            session = next
            if next.terminal.window == nil { attach() }
        }

        func detach() {
            if let terminal = session?.terminal, terminal.superview === self { terminal.removeFromSuperview() }
            session = nil
        }

        @objc private func attach() {
            guard let terminal = session?.terminal else { return }
            terminal.removeFromSuperview()
            terminal.frame = bounds
            terminal.autoresizingMask = [.width, .height]
            addSubview(terminal)
            terminal.requestRedraw()
            window?.makeFirstResponder(terminal)
        }

        override func willRemoveSubview(_ subview: NSView) {
            if subview === session?.terminal { showButton.isHidden = false }
            super.willRemoveSubview(subview)
        }

        override func didAddSubview(_ subview: NSView) {
            super.didAddSubview(subview)
            if subview === session?.terminal { showButton.isHidden = true }
        }
    }
}

private final class MountedTerminalView: LocalProcessTerminalView {
    var launch: ((LocalProcessTerminalView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        launchIfReady()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        launchIfReady()
    }

    private func launchIfReady() {
        // A fast shell can finish before SwiftUI attaches and sizes the terminal.
        guard let launch, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        self.launch = nil
        launch(self)
    }
}
