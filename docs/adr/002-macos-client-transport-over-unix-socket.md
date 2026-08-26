# ADR-002: macOS client transport over the daemon's Unix socket

## Context

ADR-001 puts the macOS app behind `throwntomd`'s HTTP/1.1 + JSON + SSE API
on a Unix socket at `~/.config/throwntom/daemon.sock`. The native macOS
client design assumed `URLSession` would carry the SSE stream, but
`URLSession` has no public API for Unix-domain sockets; only TCP and TLS
endpoints are reachable through it. The daemon deliberately has no TCP
listener and no authentication in this iteration, so the app needs its own
way onto the socket.

Options considered:

1. `NWConnection` (Network.framework) to `NWEndpoint.unix(path:)` plus a
   minimal hand-written HTTP/1.1 client: request writer, status/header
   parser, `Content-Length` and chunked body reader, SSE frame splitter.
2. POSIX `socket()`/`connect()` with `DispatchIO`, same parser as option 1.
3. A `URLProtocol` subclass bridging option 1 into `URLSession` so the rest
   of the app can use `URLSession.bytes(for:)`.
4. Add a loopback TCP listener to the daemon so `URLSession` works as
   originally written.

## Decision

Option 1, behind a thin seam. The client library defines

```swift
protocol DaemonTransport {
    func request(_ method: String, _ path: String, body: Data?) async throws
        -> (status: Int, body: Data)
    func events(_ path: String) -> AsyncThrowingStream<Data, Error>
}
```

with one implementation, `UnixSocketTransport`, built on `NWConnection`.
Each request/response uses its own connection (`Connection: close`); the
event stream holds one long-lived connection and yields the `data:` payload
of every `event: state` frame. The HTTP and SSE parsing are pure functions
over `Data` so they are unit-tested without a socket; the transport and
`DaemonClient` are tested under XCTest against a real `throwntomd` on a
temporary socket, matching the Go side's "no mocks of Core" rule.

Concurrency is Swift structured concurrency: `async`/`await` for
request/response and `AsyncThrowingStream` for events, so `DaemonClient`
can `for await` the stream in a single task and reconnect with backoff
under normal task cancellation.

The parser is written for a single trusted peer (`net/http`) but bounds
header and frame sizes and throws on malformed input instead of trapping.
The app is not sandboxed: App Sandbox cannot reach a socket outside the
app container.

## Trade-offs

- We own an HTTP parser. Accepted: the peer is fixed and small (no
  compression, redirects, pipelining, or TLS), and the alternative is
  either a third-party client (disallowed) or option 4.
- Option 4 would have kept `URLSession` but opens an unauthenticated port
  on the machine, exactly the exposure the design defers until auth exists.
- Option 3 adds an adapter layer with no consumer; nothing in the app wants
  `URLSession` semantics.
- Option 2 is option 1 with worse cancellation and connection-state
  ergonomics.
- The `DaemonTransport` seam is the only forward-looking piece: a TCP
  implementation (with auth) can be added later without touching
  `DaemonClient`. Nothing else is built ahead of need.
