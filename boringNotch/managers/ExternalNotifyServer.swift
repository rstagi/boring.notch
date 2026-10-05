import Combine
import Darwin
import Foundation
import os

/// Publishes decoded notifications on the main actor. Transport work stays off the UI thread.
@MainActor
final class ExternalNotifyServer: ObservableObject {
    static let shared = ExternalNotifyServer()
    nonisolated static let defaultSocketURL: URL = {
        // NSHomeDirectory points inside the container when sandboxed; adapters use the real home.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/boringNotch", isDirectory: true)
            .appendingPathComponent("notify.sock")
    }()

    @Published private(set) var activityQueue = AgentActivityQueue()
    @Published private(set) var isRunning = false
    let socketURL: URL

    private nonisolated static let logger = os.Logger(subsystem: "theboringteam.boringnotch", category: "ExternalNotify")
    private var listener: ExternalNotifySocketListener?
    private var generation = UUID()
    private var activityTask: Task<Void, Never>?

    init(socketURL: URL = ExternalNotifyServer.defaultSocketURL) {
        self.socketURL = socketURL
    }

    func focus(id: String, runCommand: @escaping @Sendable (String) async throws -> Void) {
        guard let event = activityQueue.events.first(where: { $0.id == id }) else { return }
        if let action = event.actions.first(where: { $0.id == "focus" }) {
            Task.detached(priority: .userInitiated) {
                do { try await runCommand(action.command) }
                catch {
                    Self.logger.error("Focus action could not launch: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        activityQueue.dismiss(id: id, at: Date())
    }

    /// Called by the view when a peek is actually on screen; republishes only when a deadline starts.
    func markPresented(id: String, revision: Int) {
        var queue = activityQueue
        guard queue.markPresented(id: id, revision: revision, at: Date()) else { return }
        activityQueue = queue
    }

    /// Called by the view when a presented peek leaves the screen; republishes only when a deadline pauses.
    func markHidden(id: String, revision: Int) {
        var queue = activityQueue
        guard queue.markHidden(id: id, revision: revision, at: Date()) else { return }
        activityQueue = queue
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try start() }
        else { stop() }
    }

    func start() throws {
        guard listener == nil else { return }
        let generation = UUID()
        self.generation = generation
        let listener = ExternalNotifySocketListener(socketURL: socketURL) { [weak self] event in
            Task { @MainActor in
                guard let self, self.isRunning, self.generation == generation else { return }
                self.activityQueue.receive(event, at: Date())
                self.scheduleActivityCycle()
                Self.logger.info("Decoded notification: \(event.id, privacy: .public) \(event.state.rawValue, privacy: .public)")
            }
        }
        try listener.start()
        self.listener = listener
        isRunning = true
        Self.logger.info("Listening at \(self.socketURL.path, privacy: .public)")
    }

    func stop() {
        generation = UUID()
        activityTask?.cancel()
        activityTask = nil
        activityQueue = AgentActivityQueue()
        listener?.stop()
        listener = nil
        isRunning = false
    }

    private func scheduleActivityCycle() {
        guard activityTask == nil else { return }
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled else { return }
                self.activityQueue.advance(at: Date())
                if self.activityQueue.events.isEmpty {
                    self.activityTask = nil
                    return
                }
            }
        }
    }
}

/// All descriptors, buffers and dispatch sources are confined to this serial queue.
private final class ExternalNotifySocketListener {
    private struct Client {
        let source: DispatchSourceRead
        var buffer = Data()
    }

    private static let maximumLineBytes = 64 * 1024
    private static let maximumClients = 32
    private static let logger = os.Logger(subsystem: "theboringteam.boringnotch", category: "ExternalNotify")

    private let socketURL: URL
    private let receive: (ExternalNotifyEvent) -> Void
    private let queue = DispatchQueue(label: "boringNotch.external-notify")
    private var listener: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private var socketIdentity: (device: dev_t, inode: ino_t)?

    init(socketURL: URL, receive: @escaping (ExternalNotifyEvent) -> Void) {
        self.socketURL = socketURL
        self.receive = receive
    }

    func start() throws {
        try queue.sync {
            let directory = socketURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            var directoryInfo = stat()
            guard lstat(directory.path, &directoryInfo) == 0,
                  directoryInfo.st_uid == getuid(),
                  directoryInfo.st_mode & S_IFMT == S_IFDIR else {
                throw posixError("Unsafe socket directory", code: EACCES)
            }
            guard chmod(directory.path, 0o700) == 0 else { throw posixError("chmod directory") }

            var address = try socketAddress()
            try removeStaleSocket(address: &address)
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw posixError("socket") }
            do {
                try makeNonblocking(descriptor)
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard result == 0 else { throw posixError("bind") }
                var info = stat()
                guard lstat(socketURL.path, &info) == 0 else { throw posixError("stat socket") }
                socketIdentity = (info.st_dev, info.st_ino)
                guard chmod(socketURL.path, 0o600) == 0 else { throw posixError("chmod socket") }
                guard listen(descriptor, 16) == 0 else { throw posixError("listen") }
                let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
                source.setEventHandler { [weak self] in self?.acceptClients(descriptor) }
                source.setCancelHandler { close(descriptor) }
                listener = source
                source.resume()
            } catch {
                close(descriptor)
                removeOwnedSocket()
                throw error
            }
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for client in clients.values { client.source.cancel() }
            clients.removeAll()
            removeOwnedSocket()
        }
    }

    private func socketAddress() throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(socketURL.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw posixError("Socket path too long", code: ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            for (index, byte) in path.enumerated() { bytes[index] = UInt8(bitPattern: byte) }
        }
        return address
    }

    private func removeStaleSocket(address: inout sockaddr_un) throws {
        var info = stat()
        guard lstat(socketURL.path, &info) == 0 else {
            guard errno == ENOENT else { throw posixError("stat existing socket") }
            return
        }
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else {
            throw posixError("Refusing to replace a non-socket or foreign socket", code: EACCES)
        }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw posixError("socket probe") }
        defer { close(probe) }
        try makeNonblocking(probe)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result < 0, errno == ECONNREFUSED else {
            throw posixError("Socket already in use", code: EADDRINUSE)
        }
        guard unlink(socketURL.path) == 0 else { throw posixError("unlink stale socket") }
    }

    private func acceptClients(_ descriptor: Int32) {
        // A bounded batch keeps a busy sender from starving other clients or shutdown.
        for _ in 0..<Self.maximumClients {
            let clientDescriptor = accept(descriptor, nil, nil)
            guard clientDescriptor >= 0 else { return }
            guard clients.count < Self.maximumClients else {
                close(clientDescriptor)
                continue
            }
            do { try makeNonblocking(clientDescriptor) }
            catch { close(clientDescriptor); continue }
            let source = DispatchSource.makeReadSource(fileDescriptor: clientDescriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.readClient(clientDescriptor) }
            source.setCancelHandler { close(clientDescriptor) }
            clients[clientDescriptor] = Client(source: source)
            source.resume()
        }
    }

    private func readClient(_ descriptor: Int32) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        for _ in 0..<16 {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count == 0 { closeClient(descriptor); return }
            if count < 0 {
                if errno == EINTR { continue }
                if errno != EAGAIN && errno != EWOULDBLOCK { closeClient(descriptor) }
                return
            }
            guard var client = clients[descriptor] else { return }
            client.buffer.append(contentsOf: bytes.prefix(count))
            while let newline = client.buffer.firstIndex(of: 0x0A) {
                let line = client.buffer.prefix(upTo: newline)
                guard line.count <= Self.maximumLineBytes else { closeClient(descriptor); return }
                if !line.isEmpty {
                    do { receive(try JSONDecoder().decode(ExternalNotifyEvent.self, from: Data(line))) }
                    catch { Self.logger.warning("Rejected notification: \(error.localizedDescription, privacy: .public)") }
                }
                client.buffer.removeSubrange(...newline)
            }
            guard client.buffer.count <= Self.maximumLineBytes else { closeClient(descriptor); return }
            clients[descriptor] = client
        }
    }

    private func closeClient(_ descriptor: Int32) {
        clients.removeValue(forKey: descriptor)?.source.cancel()
    }

    private func removeOwnedSocket() {
        guard let identity = socketIdentity else { return }
        var info = stat()
        if lstat(socketURL.path, &info) == 0,
           info.st_dev == identity.device, info.st_ino == identity.inode {
            unlink(socketURL.path)
        }
        socketIdentity = nil
    }

    private func makeNonblocking(_ descriptor: Int32) throws {
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw posixError("fcntl") }
    }

    private func posixError(_ operation: String, code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
            NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"
        ])
    }
}
