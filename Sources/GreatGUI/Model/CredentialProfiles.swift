import Foundation
import Observation
import Registry
import Runner
import Secrets

/// A local recipe for using existing Keychain items. It only holds references and check instructions.
struct CredentialProfile: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var label = ""
    var destination = ""
    var bindings = ""
    var file = ""
    var fileUse: FileUse = .environment
    var checkCommand = ""

    enum FileUse: String, Codable, CaseIterable {
        case environment
        case localFile
    }

    var envFile: String? { file.isEmpty || fileUse != .environment ? nil : file }
    var requiredLocalFile: String? { file.isEmpty || fileUse != .localFile ? nil : file }

    func environment() throws -> [String: EnvValue] {
        // Use the registry parser's grammar without echoing invalid input back to the sheet.
        guard let env = try? RegistryWriter.parseEnvs(bindings),
              env.values.allSatisfy({ value in
                  if case .keychain(let name) = value { return SecretStore.isValidName(name) }
                  return false
              }) else {
            throw RegistryError("Use Keychain references in credential bindings",
                                fix: "Use VARIABLE=keychain:secret-name. Add the value in Secrets.")
        }
        return env
    }
}

@MainActor
@Observable
final class CredentialProfiles {
    private(set) var entries: [CredentialProfile]
    var draft = CredentialProfile()
    var editorOpen = false
    var note: AppModel.Note?
    private(set) var checking: CredentialProfile.ID?
    private(set) var results: [CredentialProfile.ID: AppModel.Note] = [:]

    private let preferences: UserDefaults
    private let key: String
    @ObservationIgnored private var process: ProcessRun?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var checkID: UUID?

    init(registryURL: URL, service: String, preferences: UserDefaults) {
        self.preferences = preferences
        key = "credentialProfiles:\(service):\(registryURL.standardizedFileURL.path)"
        entries = preferences.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([CredentialProfile].self, from: $0) } ?? []
    }

    func open(_ profile: CredentialProfile = CredentialProfile()) {
        draft = profile
        note = nil
        editorOpen = true
    }

    @discardableResult
    func save() -> Bool {
        do {
            var profile = draft
            profile.label = profile.label.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.destination = profile.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.checkCommand = profile.checkCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profile.label.isEmpty, !profile.destination.isEmpty else {
                throw RegistryError("A label and destination are required")
            }
            guard !entries.contains(where: {
                $0.id != profile.id && $0.label.caseInsensitiveCompare(profile.label) == .orderedSame
            }) else { throw RegistryError("A credential profile already uses that label") }
            let env = try profile.environment()
            guard !env.isEmpty || !profile.file.isEmpty else {
                throw RegistryError("Choose at least one Keychain credential")
            }
            profile.bindings = RegistryWriter.envSpec(env)
            var updated = entries
            if let i = updated.firstIndex(where: { $0.id == profile.id }) { updated[i] = profile }
            else { updated.append(profile) }
            try persist(updated)
            results.removeValue(forKey: profile.id)
            note = nil
            editorOpen = false
            return true
        } catch let error as RegistryError {
            note = AppModel.Note(ok: false, text: error.what, fix: error.fix)
        } catch {
            note = AppModel.Note(ok: false, text: "Could not save the credential profile")
        }
        return false
    }

    func remove(_ profile: CredentialProfile) {
        do {
            try persist(entries.filter { $0.id != profile.id })
            results.removeValue(forKey: profile.id)
        } catch {
            note = AppModel.Note(ok: false, text: "Could not remove the credential profile")
        }
    }

    func invalidateChecks() {
        results = [:]
        checkID = nil
        checking = nil
        timeout?.cancel()
        timeout = nil
        process?.terminate()
        process = nil
    }

    private func persist(_ updated: [CredentialProfile]) throws {
        preferences.set(try JSONEncoder().encode(updated), forKey: key)
        entries = updated
    }

    func check(_ profile: CredentialProfile, files: [SecretFile], secrets: SecretStore) {
        guard checking == nil else { return }
        let runID = UUID()
        checkID = runID
        checking = profile.id
        results.removeValue(forKey: profile.id)
        Task { [weak self] in
            let preparation = await Task.detached(priority: .userInitiated) {
                Self.prepareCheck(profile, files: files, secrets: secrets)
            }.value
            guard let self, checkID == runID else { return }
            switch preparation {
            case .failure(let problem):
                finish(runID, .init(ok: false, text: problem.what, fix: problem.fix))
            case .success(let built):
                if profile.checkCommand.isEmpty {
                    finish(runID, .init(ok: true, text: "Credentials available", fix: "A live check can be added in Edit."))
                } else {
                    startCheck(profile, built: built, runID: runID)
                }
            }
        }
    }

    private nonisolated static func prepareCheck(_ profile: CredentialProfile, files: [SecretFile], secrets: SecretStore)
        -> Result<RunEnvironment.Built, RunEnvironment.Refusal> {
        do {
            if let name = profile.requiredLocalFile {
                guard let file = files.first(where: { $0.name == name }) else {
                    return .failure(.init(what: "Credential file \(name) is missing from the registry", fix: "Add its file reference in Secrets."))
                }
                let state = try FileSecrets(store: secrets).state(name: name, path: file.expandedPath, mode: file.modeBits)
                guard state == .inSync else {
                    return .failure(.init(what: "Credential file \(name) is \(state.words)", fix: state.advice))
                }
            }
            let resolved = Resolved(name: profile.label, run: profile.checkCommand, env: try profile.environment(), envFile: profile.envFile)
            return .success(try RunEnvironment.build(resolved, secrets: secrets))
        } catch let error as RunEnvironment.Refusal {
            return .failure(error)
        } catch {
            return .failure(.init(what: "Could not check the credential references", fix: "Check Keychain access and the file setup in Secrets."))
        }
    }

    private func startCheck(_ profile: CredentialProfile, built: RunEnvironment.Built, runID: UUID) {
        let run = ProcessRun(run: profile.checkCommand, env: built.env, redact: built.redact) { [weak self] event in
            guard case .exited(let code, _) = event else { return }
            Task { @MainActor in
                self?.finish(runID, .init(ok: code == 0,
                                      text: code == 0 ? "Live check passed" : "Live check failed (exit \(code))"))
            }
        }
        do {
            try run.start()
            process = run
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, checkID == runID else { return }
                process?.terminate()
                finish(runID, .init(ok: false, text: "Live check timed out"))
            }
        } catch {
            finish(runID, .init(ok: false, text: "Could not start the live check"))
        }
    }

    private func finish(_ runID: UUID, _ result: AppModel.Note) {
        guard checkID == runID, let id = checking else { return }
        checkID = nil
        timeout?.cancel()
        timeout = nil
        process = nil
        results[id] = result
        checking = nil
    }
}
