import Darwin
import Foundation

/// An advisory, exclusive lock on the config directory (flock(2) on a `.lock`
/// file inside it). The GUI and a launchd `scan-once` job share ledger.json
/// and journal.jsonl with last-writer-wins semantics — two processes running
/// at once can clobber each other's records (double classification, double
/// moves, interleaved journal lines). The lock is held for the owner's
/// lifetime; the kernel releases it automatically if the process dies, so a
/// crash can never wedge future runs.
final class ProcessLock {
    private let fileDescriptor: Int32
    private var released = false

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    /// Try to take the exclusive lock without blocking. Returns nil when
    /// another process (or another live lock in this one) already holds it.
    static func acquire(directory: URL = ConfigStore.directory) -> ProcessLock? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(".lock").path
        // O_CLOEXEC: without it any child process inherits the descriptor, and
        // because a flock belongs to the open file description the child would
        // keep the lock alive after this process died — exactly what the
        // "the kernel releases it when the process dies" promise rules out.
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            Log.app.error("process lock: cannot open \(path, privacy: .public) (errno \(errno))")
            return nil
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            // EWOULDBLOCK is the expected "someone else has it"; anything else
            // means the mechanism itself is broken and shouldn't look the same.
            if errno != EWOULDBLOCK {
                Log.app.error("process lock: flock failed (errno \(errno))")
            }
            close(fd)
            return nil
        }
        return ProcessLock(fileDescriptor: fd)
    }

    func release() {
        guard !released else { return }
        released = true
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    deinit { release() }
}
