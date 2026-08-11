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

extension Cache.Entry {
    /// State machine for cache entry lifecycle.
    ///
    /// ## States
    ///
    /// ```
    /// ┌─────────┐
    /// │ empty   │──compute──▶┌────────────┐
    /// └─────────┘            │ computing  │
    ///                        │ (waiters)  │
    ///                        └────────────┘
    ///                             │
    ///              ┌─────────────┴─────────────┐
    ///              ▼                           ▼
    ///        ┌─────────┐                ┌──────────┐
    ///        │ ready   │                │ failed   │
    ///        │ (value) │                │ (error)  │
    ///        └─────────┘                └──────────┘
    /// ```
    ///
    /// ## Transitions
    ///
    /// - `empty` → `computing`: First request starts computation
    /// - `computing` → `ready`: Computation succeeds
    /// - `computing` → `failed`: Computation fails or is cancelled
    ///
    /// ## Thread Safety
    ///
    /// State transitions occur under the cache's mutex.
    /// Computation runs outside the lock.
    @usableFromInline
    enum State: Sendable {
        /// No value, no computation in progress.
        case empty

        /// Computation in progress with waiting tasks.
        ///
        /// Waiters is a reference type to make State Copyable
        /// for pattern matching while holding ~Copyable queue.
        case computing(Waiters)

        /// Value successfully computed and cached.
        case ready(Value)

        /// Computation failed with error.
        case failed(Failure)
    }
}
