import CoreServices
import Foundation

/// Watches folders recursively with FSEvents and reports the paths that changed.
final class FolderWatcher {
    typealias Handler = @Sendable ([String]) -> Void

    private let paths: [String]
    private let latency: CFTimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.dillankerai.strata.folder-watcher")
    private var stream: FSEventStreamRef?

    init(paths: [String], latency: CFTimeInterval = 0.3, handler: @escaping Handler) {
        self.paths = paths
        self.latency = latency
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
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

    func stop() {
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
    private var source: DispatchSourceFileSystemObject?
    private var isStopped = false

    init(url: URL, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in self?.arm() }
    }

    func stop() {
        isStopped = true
        source?.cancel()
        source = nil
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
