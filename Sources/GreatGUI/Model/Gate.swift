import Foundation
import LocalAuthentication

/// Touch ID or the login password before a gated command runs. Asked every time, with the command's name.
enum Gate {
    enum Outcome: Equatable {
        case allowed
        case cancelled
        case failed(String)
    }

    @MainActor
    static func ask(_ reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            return .failed(problem?.localizedDescription ?? "authentication is not available on this Mac")
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .allowed : .failed("not recognised")
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            default: return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
