import Foundation
import CoreServices

/// After the first scan, an FSEvents watcher maintains deltas. Elbowroom's
/// posture is quiet: events only mark the model dirty; a rescan runs after a
/// stretch of quiet, or on the next activation, never mid-typing.
public final class FSWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "elbowroom.fsevents")

    /// `latency` is FSEvents coalescing; the caller debounces on top.
    public init?(paths: [String], latency: TimeInterval = 5, onChange: @escaping () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagNoDefer)
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

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
