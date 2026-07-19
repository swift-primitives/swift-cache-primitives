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

public import Array_Primitive
public import Array_Primitives
public import Async_Primitives
public import Async_Waiter_Primitives
public import Buffer_Linear_Primitive
public import Buffer_Primitive
public import Buffer_Ring_Primitive
public import Column_Primitives
public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
internal import Ownership_Primitives
public import Queue_Primitives
public import Standard_Library_Extensions
public import Storage_Contiguous_Primitives

/// A compute-once cache with in-flight coordination.
///
/// `Cache` provides efficient key-based caching where:
/// - First request for a key computes the value
/// - Concurrent requests for the same key wait for the first computation
/// - Subsequent requests return the cached result
///
/// ## Design
///
/// Unlike `Pool` (borrow → use → return), `Cache` uses compute-once semantics:
/// - Values are computed lazily on first access
/// - Computed values are shared forever (or until explicitly removed)
/// - Multiple waiters coordinate via `Async.Waiter` primitives
///
/// ## Thread Safety
///
/// All operations are internally synchronized via mutex. The computation
/// closure runs **outside** the lock to prevent deadlock.
///
/// ## Usage
///
/// ```swift
/// let cache = Cache<String, User>()
///
/// // First call computes, concurrent calls wait
/// let user = try await cache.value(for: "user-123") {
///     try await fetchUser(id: "user-123")
/// }
///
/// // Subsequent calls return cached value
/// let sameUser = try await cache.value(for: "user-123") {
///     fatalError("Never called - value already cached")
/// }
/// ```
///
/// ## Cancellation
///
/// Waiting tasks can be cancelled. Cancellation resumes the waiter promptly
/// with `Cache.Error.cancelled` — it does not wait for the producer to
/// publish, so a waiter is never stranded by a `compute` closure that never
/// returns. If the computing task itself is cancelled (or otherwise fails),
/// current waiters still receive that error, but the entry does not stay
/// poisoned: it resets so the next request recomputes.
public struct Cache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    @usableFromInline
    let _storage: Storage

    /// Creates an empty cache.
    @inlinable
    public init() {
        self._storage = Storage()
    }
}

// MARK: - Value Capture

extension Cache {
    /// Captures the outer `Value` generic parameter under a non-shadowable name.
    ///
    /// Nested effect types (``Evict``, ``Compute``) must declare
    /// `typealias Value = Void` or `typealias Value = _Value` to satisfy
    /// `Effect.Protocol.Value`. This shadows the outer `Value` generic
    /// parameter. `_Value` provides an escape hatch to reference the
    /// cache's value type from within those nested scopes.
    ///
    /// - SeeAlso: `Experiments/cache-effect-type-nesting/` for empirical
    ///   verification of this workaround.
    public typealias _Value = Value
}

// MARK: - Value Retrieval

extension Cache {
    /// Gets a cached value or computes it if not present.
    ///
    /// ## Behavior
    ///
    /// 1. If value is cached → returns immediately
    /// 2. If computation in progress → waits for result
    /// 3. If not present → starts computation, others wait
    ///
    /// ## In-Flight Coordination
    ///
    /// Multiple concurrent requests for the same key coordinate:
    /// - First request becomes the "producer" and computes the value
    /// - Subsequent requests become "waiters" and suspend
    /// - When computation completes, all waiters are resumed
    ///
    /// ## Cancellation
    ///
    /// - Waiting tasks can be cancelled
    /// - Cancellation resumes the waiter promptly with `.cancelled`, even if
    ///   the producer's `compute` closure is still running (or hung)
    /// - If the computing task is cancelled, current waiters receive the
    ///   error, but the entry resets rather than staying poisoned
    ///
    /// - Parameters:
    ///   - key: The key to look up or compute for.
    ///   - compute: Closure that computes the value if not cached.
    ///              Runs outside the lock to prevent deadlock.
    /// - Returns: The cached or computed value.
    /// - Throws: `Cache.Error.computeFailed` if computation throws,
    ///           `Cache.Error.cancelled` if cancelled while waiting.
    public func value(
        for key: Key,
        // reason: structural bottom-out — the compute closure's error type
        // is not generic on Cache; it is boxed into Cache.Error.computeFailed
        // (any Swift.Error). Typing this closure would need a generic-error
        // redesign of the whole Cache/Action/Entry.State chain.
        // swiftlint:disable:next typed_throws_required
        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value {
        // Phase 1: Check state under lock, determine action
        let action = _storage.withLock { state -> Action in
            guard let entry = state.entries[key] else {
                // No entry - create one and become the producer
                let entry = Entry()
                entry.state = .computing(Entry.Waiters())
                state.entries[key] = entry
                return .compute(key, entry)
            }
            switch entry.state {
            case .ready(let value):
                // Already cached - return immediately
                return .returnValue(value)

            case .failed(let error):
                // Defensive: failed entries are removed from the dictionary
                // at publish time (F-001), so a fresh lookup should never
                // observe `.failed`. If it somehow does, propagate the error
                // rather than caching it further.
                return .throwError(error)

            case .computing:
                // Computation in progress - become a waiter
                return .wait(key, entry)

            case .empty:
                // Entry exists but empty - become the producer
                entry.state = .computing(Entry.Waiters())
                return .compute(key, entry)
            }
        }

        // Phase 2: Execute action outside lock
        switch action {
        case .returnValue(let value):
            return value

        case .throwError(let error):
            throw Error.computeFailed(error)

        case .wait(_, let entry):
            return try await waitForValue(entry: entry)

        case .compute(let key, let entry):
            return try await computeAndPublish(key: key, entry: entry, compute: compute)
        }
    }
}

// MARK: - Wait for Value

extension Cache {
    /// Waits for an in-progress computation to complete.
    ///
    /// Suspends the current task until the producer completes.
    /// Supports cancellation via `Async.Waiter.Flag`.
    @usableFromInline
    func waitForValue(entry: Entry) async throws(Self.Error) -> Value {
        let flag = Async.Waiter.Flag()

        let outcome: Entry.Waiters.Outcome
        do {
            outcome = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let resumption = _storage.withLock { _ -> Async.Waiter.Resumption? in
                        switch entry.state {
                        case .ready(let value):
                            // Race: computation completed before we could wait
                            return Async.Waiter.Resumption {
                                continuation.resume(returning: .success(value))
                            }

                        case .failed(let error):
                            // Race: computation failed before we could wait
                            return Async.Waiter.Resumption {
                                continuation.resume(returning: .failure(error))
                            }

                        case .computing(let waiters):
                            // Defensive: if the task was already cancelled
                            // before we reached registration (e.g. cancelled
                            // synchronously as part of entering
                            // `withTaskCancellationHandler`, before this
                            // closure runs), do not enqueue - resume
                            // immediately instead. `onCancel` firing
                            // concurrently is safe: `flag.cancel()` is
                            // idempotent, and a resulting
                            // `pumpCancelledWaiters` call simply finds
                            // nothing left to reap. See F-002.
                            if flag.cancelled {
                                return Async.Waiter.Resumption {
                                    continuation.resume(returning: .failure(CancellationError()))
                                }
                            }

                            // Add ourselves to the waiter queue
                            let asyncContinuation = Async.Continuation<Entry.Waiters.Outcome> { outcome in
                                continuation.resume(returning: outcome)
                            }
                            let waiterEntry = Async.Waiter.Entry(
                                continuation: asyncContinuation,
                                flag: flag
                            )
                            waiters.queue.enqueue(waiterEntry)
                            entry.state = .computing(waiters)
                            return nil  // Suspended - no immediate resumption

                        case .empty:
                            // Entry was reset - treat as error
                            return Async.Waiter.Resumption {
                                continuation.resume(throwing: Error.cancelled)
                            }
                        }
                    }

                    // Resume outside lock if needed
                    resumption?.resume()
                }
            } onCancel: {
                // Set the flag, then remove this waiter from the queue and
                // resume it immediately with `.cancelled` - do not leave it
                // stranded until the producer eventually publishes (which
                // may never happen if `compute` hangs). See F-002.
                if flag.cancel() {
                    Task { self.pumpCancelledWaiters(entry: entry) }
                }
            }
        } catch {
            throw .cancelled
        }

        // Unwrap the result
        switch outcome {
        case .success(let value):
            return value

        case .failure(let error):
            if error is CancellationError {
                throw .cancelled
            }
            throw .computeFailed(error)
        }
    }
}

// MARK: - Cancellation Pump

extension Cache {
    /// Reaps and resumes cancelled waiters for a single entry immediately,
    /// without waiting for the producer to publish.
    ///
    /// Called from `waitForValue`'s cancellation handler after a waiter's
    /// flag transitions to cancelled. Without this pump, a waiter cancelled
    /// while the producer's `compute` closure is still running (or hung)
    /// would stay suspended until publish. Mirrors the reap-under-lock,
    /// resume-outside-lock pattern `Async.Semaphore.pumpWaiters()` uses over
    /// the same `Async.Waiter.Queue.Unbounded.reapFlagged(into:)` primitive.
    /// See F-002.
    @usableFromInline
    func pumpCancelledWaiters(entry: Entry) {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { _ in
            guard case .computing(let waiters) = entry.state else {
                // Already published (or reset) - nothing left to reap.
                return
            }

            var flagged = Async.Waiter.Queue.Drain<
                Async.Waiter.Queue.Flagged<Entry.Waiters.Outcome, Void>
            >()
            waiters.queue.reapFlagged(into: &flagged)

            while let flaggedEntry = flagged.dequeue() {
                resumptions.append(
                    flaggedEntry.resumption { _ in .failure(CancellationError()) }
                )
            }
        }

        // Resume outside lock
        resumptions.drain { $0.resume() }
    }
}

// MARK: - Compute and Publish

extension Cache {
    /// Computes a value and publishes it to all waiters.
    ///
    /// Runs the computation outside the lock, then publishes
    /// the result to all waiting tasks.
    @usableFromInline
    func computeAndPublish(
        key: Key,
        entry: Entry,
        // reason: structural bottom-out — the compute closure's error type
        // is not generic on Cache; it is boxed into Cache.Error.computeFailed
        // (any Swift.Error). Typing this closure would need a generic-error
        // redesign of the whole Cache/Action/Entry.State chain.
        // swiftlint:disable:next typed_throws_required
        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value {
        // Run computation outside lock
        // reason: structural bottom-out — mirrors Cache.Error.computeFailed.
        // swiftlint:disable no_any_protocol_existential
        let result: Result<Value, any Swift.Error>
        // swiftlint:enable no_any_protocol_existential
        do {
            let value = try await compute()
            result = .success(value)
        } catch {
            result = .failure(error)
        }

        // Publish result under lock, collect resumptions
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { state in
            guard case .computing(let waiters) = entry.state else {
                // State changed unexpectedly - shouldn't happen
                return
            }

            // Update state based on result
            switch result {
            case .success(let value):
                entry.state = .ready(value)

            case .failure(let error):
                // Deliver the error to the producer and current waiters,
                // but do NOT cache it: remove the entry so the next
                // request recomputes (the README's non-poisoning promise,
                // F-001). The entry object itself still transitions to
                // `.failed` for any late waiter that captured the entry
                // reference in phase 1 but has not registered yet - it
                // raced the failing computation and receives the error.
                entry.state = .failed(error)
                if state.entries[key] === entry {
                    state.entries.removeValue(forKey: key)
                }
            }

            // Collect all waiter resumptions
            waiters.queue.drain { waiterEntry in
                // Check if waiter was cancelled
                if waiterEntry.flag.cancelled {
                    resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                } else {
                    resumptions.append(waiterEntry.resumption(with: result))
                }
            }
        }

        // Resume all waiters outside lock
        resumptions.drain { $0.resume() }

        // Return or throw based on our own computation result
        switch result {
        case .success(let value):
            return value

        case .failure(let error):
            throw Error.computeFailed(error)
        }
    }
}

// MARK: - Read Operations

extension Cache {
    /// Gets a cached value if present (no computation).
    ///
    /// Returns immediately without blocking.
    /// Does not trigger computation for missing keys.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The cached value, or `nil` if not cached or still computing.
    @inlinable
    public func cachedValue(for key: Key) -> Value? {
        _storage.withLock { state in
            guard let entry = state.entries[key] else {
                return nil
            }
            if case .ready(let value) = entry.state {
                return value
            }
            return nil
        }
    }

    /// Whether a value is cached for the given key.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if a value is cached (not computing or failed).
    @inlinable
    public func contains(key: Key) -> Bool {
        cachedValue(for: key) != nil
    }

    /// The number of cached entries.
    ///
    /// Includes entries in all states (empty, computing, ready, failed).
    @inlinable
    public var count: Int {
        _storage.withLock { state in
            state.entries.count
        }
    }

    /// Whether the cache has any entries.
    @inlinable
    public var isEmpty: Bool {
        _storage.withLock { state in
            state.entries.isEmpty
        }
    }
}

// MARK: - Write Operations

extension Cache {
    /// Explicitly sets a cached value, bypassing computation.
    ///
    /// If the key already has a value or computation in progress,
    /// this overwrites it. Waiters for a computing entry will receive
    /// the new value.
    ///
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The key to cache under.
    @inlinable
    public func setValue(_ value: Value, for key: Key) {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { state in
            // Check for existing waiters
            if let existingEntry = state.entries[key],
                case .computing(let waiters) = existingEntry.state
            {
                waiters.queue.drain { waiterEntry in
                    resumptions.append(waiterEntry.resumption(with: .success(value)))
                }
            }

            // Create or update entry with ready state
            let entry = Entry()
            entry.state = .ready(value)
            state.entries[key] = entry
        }

        // Resume waiters outside lock
        resumptions.drain { $0.resume() }
    }

    /// Removes a cached value.
    ///
    /// If computation is in progress, waiters will receive a cancelled error.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: The removed value, if one was cached.
    @discardableResult
    @inlinable
    public func removeValue(for key: Key) -> Value? {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        let value = _storage.withLock { state -> Value? in
            guard let entry = state.entries.removeValue(forKey: key) else {
                return nil
            }

            switch entry.state {
            case .ready(let value):
                return value

            case .computing(let waiters):
                // Cancel all waiters
                waiters.queue.drain { waiterEntry in
                    resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                }
                return nil

            case .empty, .failed:
                return nil
            }
        }

        // Resume waiters outside lock
        resumptions.drain { $0.resume() }

        return value
    }

    /// Removes all cached values.
    ///
    /// Any in-progress computations will have their waiters cancelled.
    @inlinable
    public func removeAll() {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { state in
            for (_, entry) in state.entries {
                if case .computing(let waiters) = entry.state {
                    waiters.queue.drain { waiterEntry in
                        resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                    }
                }
            }

            state.entries.removeAll()
        }

        // Resume waiters outside lock
        resumptions.drain { $0.resume() }
    }
}

// MARK: - Conditional Operations

extension Cache {
    /// Gets a cached value or computes it, with optional condition.
    ///
    /// Like `value(for:compute:)` but allows skipping computation
    /// based on a condition.
    ///
    /// - Parameters:
    ///   - key: The key to look up or compute for.
    ///   - shouldCompute: Whether to compute if not cached. If `false`
    ///                    and not cached, returns `nil`.
    ///   - compute: Closure that computes the value if not cached.
    /// - Returns: The cached or computed value, or `nil` if computation skipped.
    /// - Throws: `Cache.Error` if computation fails or task cancelled.
    public func value(
        for key: Key,
        if shouldCompute: Bool,
        // reason: structural bottom-out — the compute closure's error type
        // is not generic on Cache; it is boxed into Cache.Error.computeFailed
        // (any Swift.Error). Typing this closure would need a generic-error
        // redesign of the whole Cache/Action/Entry.State chain.
        // swiftlint:disable:next typed_throws_required
        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value? {
        // Quick check for cached value
        if let cached = cachedValue(for: key) {
            return cached
        }

        // If we shouldn't compute, return nil
        guard shouldCompute else {
            return nil
        }

        // Compute normally
        return try await value(for: key, compute: compute)
    }
}
