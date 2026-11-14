import CoreServices
import Foundation

/// Watches folders recursively with FSEvents and reports the paths that changed.
final class FolderWatcher {
    typealias Handler = @Sendable ([String]) -> Void

    private let paths: [String]
    private let latency: CFTimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.dillankerai.strata.folder-watcher")
    private let queueKey = DispatchSpecificKey<Void>()
    private var stream: FSEventStreamRef?

    init(paths: [String], latency: CFTimeInterval = 0.3, handler: @escaping Handler) {
        self.paths = paths
        self.latency = latency
        self.handler = handler
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    func start() {
        onQueue(startStream)
    }

    /// Stops on the callback queue, so no callback is still using this object when it returns.
    func stop() {
        onQueue(stopStream)
    }

    /// Runs inline when already on the queue: a callback's reference can be the last one, putting deinit there.
    private func onQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func startStream() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            if !changed.isEmpty { watcher.handler(changed) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Watches one file, such as `~/.claude.json`, which Claude Code replaces atomically. Re-arms after renames and deletes.
final class FileWatcher {
    typealias Handler = @Sendable () -> Void

    private let url: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.dillankerai.strata.file-watcher")
    private let queueKey = DispatchSpecificKey<Void>()
    private var source: DispatchSourceFileSystemObject?
    private var isStopped = false

    init(url: URL, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in self?.arm() }
    }

    func stop() {
        let work = {
            self.isStopped = true
            self.source?.cancel()
            self.source = nil
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func arm() {
        guard !isStopped, source == nil else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.arm() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.handler()
            if source.data.contains(.delete) || source.data.contains(.rename) {
                source.cancel()
                self.source = nil
                self.queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arm() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }
}
