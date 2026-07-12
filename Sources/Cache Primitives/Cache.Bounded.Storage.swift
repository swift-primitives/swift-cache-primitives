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
public import Async_Primitives
public import Ownership_Primitives

extension Cache.Bounded {
    /// Reference storage for the bounded cache.
    ///
    /// Uses `Ownership.Mutable.Unchecked` to give `Cache.Bounded` reference
    /// semantics while keeping a struct interface. Thread safety is provided
    /// by the wrapped `Async.Mutex`, mirroring ``Cache/Storage``.
    @usableFromInline
    struct Storage: Sendable {
        @usableFromInline
        let _storage: Ownership.Mutable<Async.Mutex<State>>.Unchecked

        @inlinable
        package init(capacity: Int) {
            self._storage = Ownership.Mutable.Unchecked(Async.Mutex(State(capacity: capacity)))
        }
    }
}

extension Cache.Bounded.Storage {
    @inlinable
    package func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout sending Cache.Bounded.State) throws(E) -> sending T) throws(E) -> sending T {
        try _storage.mutable.value.withLock(body)
    }
}
