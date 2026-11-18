import AppKit
import SwiftUI
import TerminalDesign

/// ⌘,: the theme, the appearance, the team's registry, updates, and where things are. Nothing here is
/// secret. Drawn in the same theme and appearance as the window.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Palette.appearanceKey) private var appearance = Palette.defaultAppearance
    @AppStorage(TermPalette.key) private var paletteRaw = TermPalette.fallback.rawValue
    @AppStorage("checkForUpdates") private var checkForUpdates = true

    var body: some View {
        @Bindable var model = model
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                look(palette).formSection("Look", palette)
                team(palette).formSection("Team", palette)
                updates(palette).formSection("Updates", palette)
                places(palette).formSection("Where things are", palette)
                Text("Keychain access follows the app's signing certificate. make install creates one on this Mac, self-signed, with nothing from Apple; make identity says which one a build uses.")
                    .font(.callout).foregroundStyle(palette.muted)
                    .formSection("Signing", palette)
            }
            .padding(20)
        }
        .frame(width: 600, height: 620)
        .foregroundStyle(palette.ink)
        .background(palette.ground)
        .tint(palette.tint)
        .preferredColorScheme(Palette.colorScheme(appearance))
        .confirmationDialog("Leave the team registry?", isPresented: $model.leaveTeamAsked, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { model.leaveTeam() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its commands and skills go from this Mac, and its folder goes to the Trash. Your own commands and every stored secret stay.")
        }
    }

    private func line<Value: View>(_ label: String, @ViewBuilder _ value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).frame(width: 130, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
    }

    private func look(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            line("Theme") {
                Picker("Theme", selection: $paletteRaw) {
                    ForEach(TermPalette.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
            }
            line("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .labelsHidden().fixedSize()
            }
            line("Mono typeface") {
                Text(TermFont.installed ? "JetBrains Mono" : "SF Mono (JetBrains Mono is not installed)").foregroundStyle(palette.muted)
            }
        }
    }

    private func team(_ palette: Palette) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            if model.teamStatus.joined {
                line("Follows") {
                    Text(model.teamStatus.remote ?? model.teamStatus.directory.path).font(Palette.mono).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                line("Status") {
                    Text(model.teamSummary).foregroundStyle(palette.muted)
                }
                HStack(spacing: 10) {
                    Button("Sync Now") { model.syncTeam() }.secondaryButton(palette).disabled(model.teamBusy || !model.teamStatus.repository)
                    Button("Leave…") { model.leaveTeamAsked = true }.secondaryButton(palette).disabled(model.teamBusy)
                }
            } else {
                LabeledField(palette: palette, label: "Repository", hint: "The git address of your team's tooling repository, as you were given it.") {
                    HStack {
                        TextField("Repository", text: $model.teamAddress, prompt: Text("https://host/team/tooling.git"))
                            .font(Palette.mono).fieldBox(palette)
                            .onSubmit { model.joinTeam() }
                        Button("Join") { model.joinTeam() }.primaryButton(palette)
                            .disabled(model.teamBusy || model.teamAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Text(model.teamSummary).font(.callout).foregroundStyle(palette.muted)
            }
            if let note = model.teamNote { NoteLine(note: note, palette: palette) }
            Text("The team's repository holds shared commands, the names of the secrets they need, and agent skills. It is cloned to \(model.teamDirectory.path), followed by the app, and read-only here: a command of yours with the same name wins. A team schedule is never armed by itself. Secret values never come from it and are never sent to it.")
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func updates(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Look for a newer version, team changes and tools that are behind", isOn: $checkForUpdates)
            line("Status") {
                Text(model.updateStatus).foregroundStyle(palette.muted)
            }
            HStack(spacing: 10) {
                Button("Check Now") { model.checkForUpdate() }.secondaryButton(palette).disabled(AppModel.checkoutURL == nil || model.checkingForUpdate)
                if model.updateAvailable != nil { Button("Update…") { model.update() }.primaryButton(palette) }
            }
            Text("It only looks: it asks the repository this copy was built from whether there is something new, and shows Update available in the sidebar. Nothing is downloaded or installed until you press Update.")
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func places(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            line("Registry") {
                Text(model.registryURL.path).font(Palette.mono).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.registryURL]) }.rowAction(palette)
            }
            line("Scheduled runs") {
                Text(model.scheduler.logsDir.path).font(Palette.mono).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.scheduler.logsDir]) }.rowAction(palette)
            }
            line("Shell") { Text(model.shellName + " · login shell").foregroundStyle(palette.muted) }
            line("Keychain service") { Text(model.secrets.service).font(Palette.mono).textSelection(.enabled) }
            line("Version") { Text(Version.full).font(Palette.mono).textSelection(.enabled) }
            line("Built from") {
                Text(AppModel.checkoutURL?.path ?? "not a checkout").font(Palette.mono).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Button("Update…") { model.update() }.rowAction(palette).disabled(AppModel.checkoutURL == nil)
            }
        }
    }
}
