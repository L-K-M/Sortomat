import CoreServices
import Foundation

/// Watches a folder subtree via FSEvents and calls `onChange` (coalesced by the
/// caller) whenever anything inside changes. FSEvents is recursive by nature and
/// survives the folder being deleted and recreated, replacing the per-folder
/// dispatch source that silently stopped after an unmount/rename (PLAN Phase 1/3).
/// Rules that aren't recursive still use this; the deeper events just trigger a
/// harmless (coalesced) rescan that the pipeline filters to the top level.
final class FSEventsWatcher {
    /// The stream's context info object, kept on its own heap allocation. The
    /// stream *retains it through the context's retain/release callbacks*, so
    /// an event already in flight on the utility queue can never call into a
    /// deallocating object: the box outlives the watcher until FSEvents has
    /// fully released the stream. (Previously the context held an unretained
    /// `self` and teardown happened in `deinit` — a use-after-free window
    /// every time the watcher set was rebuilt.)
    private final class Callback {
        let onChange: () -> Void
        init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    }

    private var stream: FSEventStreamRef?
    private let box: Callback
    private let queue = DispatchQueue(label: "ch.lkmc.Sortomat.fsevents", qos: .utility)
    /// The (unexpanded) path this watcher was created for, so the owner can
    /// diff the wanted set against live watchers instead of rebuilding all.
    let path: String

    init?(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.box = Callback(onChange)
        let expanded = (path as NSString).expandingTildeInPath

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<Callback>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue().onChange()
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
