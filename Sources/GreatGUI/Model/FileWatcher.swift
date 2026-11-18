import Foundation

/// Calls back when a file changes, including the atomic save-by-rename editors do.
final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        arm()
    }

    deinit { cancel() }

    private func arm() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // Not there yet: look again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.arm() }
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .delete, .rename], queue: .main)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let events = s.data
            self.onChange()
            if events.contains(.delete) || events.contains(.rename) {
                self.cancel()
                // A second save can land while the new file is not yet watched: read once more after re-arming.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.arm()
                    self?.onChange()
                }
            }
        }
        s.setCancelHandler { [fd] in close(fd) }
        s.resume()
        source = s
    }

    private func cancel() {
        source?.cancel()
        source = nil
        fd = -1
    }
}
