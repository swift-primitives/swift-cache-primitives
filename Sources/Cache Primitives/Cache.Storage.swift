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

public import Async_Mutex_Primitives
public import Ownership_Primitives

#if DEBUG
    internal import Synchronization
#endif

extension Cache {
    /// Reference storage for the cache.
    ///
    /// Uses `Ownership.Mutable.Unchecked` to give Cache reference semantics
    /// while keeping a struct interface. Thread safety is provided by the
    /// wrapped `Async.Mutex`.
    @usableFromInline
    struct Storage: Sendable {
        @usableFromInline
        let _storage: Ownership.Mutable<Async.Mutex<State>>.Unchecked

        #if DEBUG
            /// Debug-only coordination that does not belong in cache state.
            ///
            /// `Storage` remains Copyable while this reference keeps the
            /// non-Copyable mutex used only by deterministic test hooks.
            final class Testing: @unchecked Sendable {
                /// Test hook called after a waiter is enqueued.
                ///
                /// The hook runs after the cache mutex is released, allowing
                /// tests to synchronize on registration without polling
                /// scheduler turns.
                let waiterEnqueued = Mutex<(@Sendable () -> Void)?>(nil)
            }

            let testing = Testing()
        #endif

        @inlinable
        package init() {
            self._storage = Ownership.Mutable.Unchecked(Async.Mutex(State()))
        }
    }
}

extension Cache.Storage {
    @inlinable
    package func withLock<T: ~Copyable, E: Swift.Error>(
        _ body: (inout sending Cache.State) throws(E) -> sending T
    ) throws(E) -> sending T {
        try _storage.mutable.value.withLock(body)
    }
}
