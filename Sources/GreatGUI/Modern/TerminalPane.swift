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

    func makeTerminal(coordinator: Coordinator) -> LocalProcessTerminalView {
        let view = MountedTerminalView(frame: .zero)
        view.processDelegate = coordinator
        view.font = TermFont.nsFont()
        Self.apply(theme, to: view)
        var env = ProcessInfo.processInfo.environment
        env.merge(run.env) { _, new in new }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let shell = ProcessRun.defaultShell()
        view.launch = { [run] terminal in
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
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [onExit] in onExit(exitCode) }
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
