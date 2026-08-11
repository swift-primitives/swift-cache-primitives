# Cache Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-cache-primitives/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-cache-primitives/actions/workflows/ci.yml)

`Cache<Key, Value, Failure>` — a thread-safe, compute-if-absent async cache.
`value(for:compute:)` returns a cached value, or runs the typed async compute
closure on a miss and stores the result. Concurrent callers requesting the same
missing key **coalesce onto a single in-flight computation** rather than each
running the work — so a burst of cache misses for one key does the expensive
work once, not N times.

---

## Key Features

- **Compute-if-absent** — `value(for:compute:)` runs the async closure only on a miss; hits return immediately.
- **Request coalescing** — concurrent misses for the same key await one shared computation (no thundering herd, no duplicate work).
- **Typed producer failures** — `Failure` remains concrete through the compute
  closure and `Cache.Error.computeFailed(Failure)`; a failed computation does
  not poison later attempts.
- **`Sendable`** — safe to share across tasks; `Key: Hashable & Sendable`, `Value: Sendable`.

---

## Quick Start

```swift
import Cache_Primitives

enum ConfigurationError: Error {
    case unavailable
}

let cache = Cache<String, Int, ConfigurationError>()

// Compute-if-absent: the closure runs once per key. Concurrent callers for the
// same key await the single in-flight computation rather than duplicating it.
let timeout = try await cache.value(for: "config.timeout") {
    () async throws(ConfigurationError) -> Int in
    try await fetchTimeout()        // your async work — only runs on a miss
}
```

## Error Handling

Cache operations throw `Cache<Key, Value, Failure>.Error`. A producer failure is
available directly as its declared type; waiter cancellation remains a separate
cache lifecycle error.

```swift
do throws(Cache<String, Int, ConfigurationError>.Error) {
    _ = try await cache.value(for: "config.timeout") {
        () async throws(ConfigurationError) -> Int in
        try await fetchTimeout()
    }
} catch {
    switch error {
    case .computeFailed(let failure):
        handle(failure)  // ConfigurationError, without a cast
    case .cancelled:
        handleCancellation()
    }
}
```

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-cache-primitives.git", branch: "main")
]
```

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Cache Primitives", package: "swift-cache-primitives")
    ]
)
```

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the corresponding Linux / Windows toolchain).

---

## Platform Support

| Platform         | CI  | Status       |
|------------------|-----|--------------|
| macOS 26         | Yes | Full support |
| Linux            | Yes | Full support |
| Windows          | Yes | Full support |
| iOS/tvOS/watchOS | —   | Supported    |
| Swift Embedded   | —   | Pending (nightly-toolchain follow-up) |

---

## Related Packages

- [`swift-async-primitives`](https://github.com/swift-primitives/swift-async-primitives) — the async coordination primitives the cache's in-flight-computation sharing is built on.
- [`swift-dictionary-primitives`](https://github.com/swift-primitives/swift-dictionary-primitives) — the keyed storage behind the cache's entry table.

---

## Community

<!-- BEGIN: discussion -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
