import Darwin
import Foundation

/// A Unix socket peer whose answers the test writes itself, byte by byte, and which records
/// everything the client sent. What the transport does with a response depends on how the bytes
/// arrive — a head split across two reads, a chunked body, a status that is not 200, a stream
/// that ends mid-head — and a real daemon cannot be asked for any of those.
///
/// Every wait is bounded: a client that never connects or never sends fails the waiting call
/// rather than parking the suite.
// Accepted descriptors, received bytes and the stop flag are only touched under `condition`.
// swiftlint:disable:next no_unchecked_sendable
final class ScriptedSocketServer: @unchecked Sendable {

  // MARK: Lifecycle

  init() throws {
    path = "/tmp/tt-script-\(UUID().uuidString.prefix(8)).sock"
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

  // MARK: Internal

  let path: String

  /// Everything the client has sent so far, in arrival order.
  var received: Data {
    condition.lock()
    defer { condition.unlock() }
    return inbound
  }

  /// How many of the client's connections the client itself has hung up. Whether the transport
  /// closes the socket it is done with cannot be seen in the response it returns.
  var closedByClient: Int {
    condition.lock()
    defer { condition.unlock() }
    return clientClosures
  }

  /// Waits for the client's request head and returns it as text, without the blank line.
  func requestHead(timeout: TimeInterval = 2) throws -> String {
    let terminator = Data("\r\n\r\n".utf8)
    let deadline = Date().addingTimeInterval(timeout)
    condition.lock()
    defer { condition.unlock() }
    while true {
      if let end = inbound.range(of: terminator) {
        return String(decoding: inbound[inbound.startIndex..<end.lowerBound], as: UTF8.self)
      }
      guard condition.wait(until: deadline) else {
        throw SocketServerError.failed("no request head within \(timeout)s")
      }
    }
  }

  /// Writes `text` to the client, waiting for it to connect first.
  func reply(_ text: String, timeout: TimeInterval = 2) throws {
    try reply(Data(text.utf8), timeout: timeout)
  }

  func reply(_ bytes: Data, timeout: TimeInterval = 2) throws {
    let descriptor = try connectedDescriptor(timeout: timeout)
    try bytes.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { return }
      var offset = 0
      while offset < buffer.count {
        let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
        guard written > 0 else { throw SocketServerError.failed("write() failed: \(errno)") }
        offset += written
      }
    }
  }

  /// Ends the response the way a daemon closing the stream does: the client's next receive
  /// reports end of stream. The peer keeps reading, so what the client sent stays readable.
  ///
  /// The pause is what makes that end of stream and not an error: Network.framework reports a
  /// close that overtakes bytes the client has not read yet as a transport failure, and 50 ms is
  /// four orders of magnitude more than a local socket read needs.
  func endReply(timeout: TimeInterval = 2) throws {
    let descriptor = try connectedDescriptor(timeout: timeout)
    Thread.sleep(forTimeInterval: 0.05)
    shutdown(descriptor, SHUT_WR)
  }

  func stop() {
    condition.lock()
    guard !isStopped else { return condition.unlock() }
    isStopped = true
    let descriptors = acceptedDescriptors
    acceptedDescriptors = []
    condition.unlock()

    Darwin.close(listener)
    for descriptor in descriptors { Darwin.close(descriptor) }
    unlink(path)
  }

  // MARK: Private

  private let listener: Int32
  private let condition = NSCondition()
  private var acceptedDescriptors = [Int32]()
  private var inbound = Data()
  private var clientClosures = 0
  private var isStopped = false

  /// The first connection the client made, once it has made one.
  private func connectedDescriptor(timeout: TimeInterval) throws -> Int32 {
    let deadline = Date().addingTimeInterval(timeout)
    condition.lock()
    defer { condition.unlock() }
    while acceptedDescriptors.isEmpty {
      guard condition.wait(until: deadline) else {
        throw SocketServerError.failed("no connection within \(timeout)s")
      }
    }
    return acceptedDescriptors[0]
  }

  private func acceptLoop() {
    while true {
      let descriptor = accept(listener, nil, nil)
      guard descriptor >= 0 else { return }
      condition.lock()
      if isStopped {
        condition.unlock()
        Darwin.close(descriptor)
        return
      }
      acceptedDescriptors.append(descriptor)
      condition.broadcast()
      condition.unlock()
      Thread.detachNewThread { [self] in readLoop(descriptor) }
    }
  }

  /// Records what the client sends, and whether the client hung up, so a test can assert on the
  /// request it made and on the socket it left behind.
  private func readLoop(_ descriptor: Int32) {
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
      guard count > 0 else {
        if count == 0 {
          condition.lock()
          clientClosures += 1
          condition.broadcast()
          condition.unlock()
        }
        return
      }
      condition.lock()
      inbound.append(contentsOf: buffer[0..<count])
      condition.broadcast()
      condition.unlock()
    }
  }

}
