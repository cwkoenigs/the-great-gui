import AppKit
import SwiftUI
import TerminalDesign

/// the-great-gui: the command window and Settings (⌘,). One look (DECISIONS local-032).
@main
struct GreatGUIApp: App {
    @AppStorage(TermPalette.key) private var paletteRaw = TermPalette.fallback.rawValue
    private let model: AppModel

    init() {
        MainActor.assumeIsolated {
            CLI.runIfRequested()
            Snapshot.runIfRequested()
        }
        model = MainActor.assumeIsolated { AppModel() }
    }

    var body: some Scene {
        WindowGroup("the-great-gui", id: "main") {
            ModernWindow()
                .id(paletteRaw)  // a new theme redraws the whole window
                .environment(model)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About the-great-gui") { model.aboutOpen = true }
            }
            CommandGroup(after: .appInfo) {
                Button(model.updateAvailable.map { "Update… (\($0.words))" } ?? "Update…") { model.update() }
                Button("Check for Updates") { model.checkForUpdate() }.disabled(AppModel.checkoutURL == nil || model.checkingForUpdate)
            }
            CommandMenu("Commands") {
                Button("New Command…") { model.openNewCommand() }.keyboardShortcut("n")
                Button("Edit Command…") { model.editSelected() }.keyboardShortcut("e").disabled(model.selectedCommand == nil)
                Button("Delete Command…") { model.deleteSelected() }.keyboardShortcut(.delete, modifiers: .command).disabled(model.selectedCommand == nil)
                Button(model.selected.map(model.isPaused) == true ? "Resume Schedule" : "Pause Schedule") { model.togglePauseSelected() }
                    .disabled(model.selectedCommand?.schedule == nil)
                Divider()
                Button("Reload Registry") { model.reload() }.keyboardShortcut("r")
                Button("Edit Registry File") { NSWorkspace.shared.open(model.registryURL) }.keyboardShortcut("e", modifiers: [.command, .option])
                Button("Reveal Registry File") { NSWorkspace.shared.activateFileViewerSelecting([model.registryURL]) }
                Divider()
                Button("Secrets…") { model.destination = .secrets }.keyboardShortcut("k")
                Button("Tools…") { model.destination = .tools }.keyboardShortcut("u")
                Button("Stop Run") { model.terminate() }.keyboardShortcut(".")
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
