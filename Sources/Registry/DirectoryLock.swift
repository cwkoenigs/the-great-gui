import Darwin
import Foundation

/// A directory stays in place while atomic writes replace the files inside it. Separate opens
/// contend across threads and processes. Closing the descriptor releases the advisory lock.
public enum DirectoryLock {
    public static func withExclusiveAccess<T>(to directory: URL, createIfMissing: Bool,
                                              _ body: () throws -> T) throws -> T {
        if createIfMissing {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return try body()
    }
}
