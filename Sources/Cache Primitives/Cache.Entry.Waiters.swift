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

public import Async_Primitives
public import Async_Waiter_Primitives
public import Memory_Heap_Primitives
public import Queue_Primitive

extension Cache.Entry {
    /// Queue of tasks waiting for computation to complete.
    ///
    /// Waiters is a reference type to allow the State enum to be Copyable
    /// while holding the ~Copyable `Async.Waiter.Queue.Unbounded`.
    @usableFromInline
    /// ## Safety Invariant
    ///
    /// Guarded by the cache's external mutex per Cache.Entry.State docstring.
    ///
    /// ## Intended Use
    ///
    /// - Waiting task queue for cache entry computation completion.
    ///
    /// ## Non-Goals
    ///
    /// - Not independently thread-safe.
    final class Waiters: @unsafe @unchecked Sendable {
        @usableFromInline
        typealias Outcome = Result<Value, any Swift.Error>

        @usableFromInline
        var queue: Async.Waiter.Queue.Unbounded<Outcome, Void>

        @inlinable
        init() {
            self.queue = Async.Waiter.Queue.Unbounded<Outcome, Void>()
        }
    }
}
