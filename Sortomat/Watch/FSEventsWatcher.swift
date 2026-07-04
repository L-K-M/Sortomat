import CoreServices
import Foundation

/// Watches a folder subtree via FSEvents and calls `onChange` (coalesced by the
/// caller) whenever anything inside changes. FSEvents is recursive by nature and
/// survives the folder being deleted and recreated, replacing the per-folder
/// dispatch source that silently stopped after an unmount/rename (PLAN Phase 1/3).
/// Rules that aren't recursive still use this; the deeper events just trigger a
/// harmless (coalesced) rescan that the pipeline filters to the top level.
final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "ch.lkmc.Sortomat.fsevents", qos: .utility)

    init?(path: String, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let expanded = (path as NSString).expandingTildeInPath

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [expanded] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,                       // latency: coalesce bursts
            flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
