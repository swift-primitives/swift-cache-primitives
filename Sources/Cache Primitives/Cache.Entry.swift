// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cache open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-cache project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

extension Cache {
    /// A cache entry that tracks computation state.
    ///
    /// Entry is a reference type to allow storage in Dictionary while
    /// containing ~Copyable waiter queues.
    @usableFromInline
    /// ## Safety Invariant
    ///
    /// All state transitions guarded by the cache's external mutex.
    ///
    /// ## Intended Use
    ///
    /// - Cache entry lifecycle tracking under mutex protection.
    ///
    /// ## Non-Goals
    ///
    /// - Not independently thread-safe; requires cache mutex.
    final class Entry: @unchecked Sendable {
        @usableFromInline
        var state: State

        @inlinable
        package init() {
            self.state = .empty
        }

        @inlinable
        package init(state: State) {
            self.state = state
        }
    }
}
