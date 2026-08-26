import Darwin
import Foundation

enum SocketServerError: Error {
    case failed(String)
}

/// A Unix socket peer that accepts connections and never replies, so a client parks in `receive`.
/// Lets transport deadline and cancellation tests run without sleeping against a real daemon.
final class StalledSocketServer: @unchecked Sendable {
    let path: String

    private let listener: Int32
    private let lock = NSLock()
    private var acceptedDescriptors: [Int32] = []
    private var isStopped = false

    init() throws {
        path = "/tmp/tt-stall-\(UUID().uuidString.prefix(8)).sock"
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw SocketServerError.failed("socket() failed: \(errno)") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw SocketServerError.failed("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, addressSize) }
        }
        guard bound == 0 else { throw SocketServerError.failed("bind() failed: \(errno)") }
        guard listen(listener, 4) == 0 else { throw SocketServerError.failed("listen() failed: \(errno)") }

        Thread.detachNewThread { [self] in acceptLoop() }
    }

    /// Holds every accepted connection open and unread until `stop()`.
    private func acceptLoop() {
        while true {
            let descriptor = accept(listener, nil, nil)
            guard descriptor >= 0 else { return }
            lock.lock()
            if isStopped {
                lock.unlock()
                Darwin.close(descriptor)
            } else {
                acceptedDescriptors.append(descriptor)
                lock.unlock()
            }
        }
    }

    func stop() {
        lock.lock()
        guard !isStopped else { return lock.unlock() }
        isStopped = true
        let descriptors = acceptedDescriptors
        acceptedDescriptors = []
        lock.unlock()

        Darwin.close(listener)
        for descriptor in descriptors { Darwin.close(descriptor) }
        unlink(path)
    }
}
