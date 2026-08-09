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

import Async_Primitives
import Synchronization
import Testing

@testable import Cache_Primitives

// MARK: - Test Support

/// A box recording a task's terminal outcome for the test body.
///
/// The waiter task under test writes its outcome here the moment it
/// resumes. A completion gate then gives the test a causal acknowledgement
/// before it reads this result.
private actor Outcome<Value: Sendable> {
    private var terminal: Terminal?
}

extension Outcome {
    enum Terminal {
        case succeeded(Value)
        case threw(any Swift.Error)
    }

    func record(_ outcome: Terminal) {
        terminal = outcome
    }

    var value: Terminal? { terminal }
}

// MARK: - Tests

/// Regression tests for `Cache` (generic-namespace source: top-level
/// `@Suite` carve-out per [INST-TEST-013]).
@Suite("Cache")
struct Tests {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    #if DEBUG
        private static func isComputing(
            in cache: Cache<String, Int>,
            for key: String
        ) -> Bool {
            cache._storage.withLock { state in
                guard let entry = state.entries[key],
                    case .computing = entry.state
                else {
                    return false
                }
                return true
            }
        }
    #endif

    @Test
    func `false conditional removal preserves a ready value`() {
        let cache = Cache<String, Int>()
        cache.setValue(42, for: "answer")

        let removed = cache.removeValue(for: "answer") { $0 != 42 }

        #expect(removed == nil)
        #expect(cache.cachedValue(for: "answer") == 42)
    }

    @Test
    func `true conditional removal removes a ready value`() {
        let cache = Cache<String, Int>()
        cache.setValue(42, for: "answer")

        let removed = cache.removeValue(for: "answer") { $0 == 42 }

        #expect(removed == 42)
        #expect(cache.cachedValue(for: "answer") == nil)
    }

    @Test
    func `a conditional removal predicate can read the same cache`() {
        let cache = Cache<String, Int>()
        cache.setValue(42, for: "answer")

        let removed = cache.removeValue(for: "answer") { value in
            cache.cachedValue(for: "answer") == value
        }

        #expect(removed == 42)
        #expect(cache.cachedValue(for: "answer") == nil)
    }

    #if DEBUG
        @Test
        func `two expired readers preserve and join a replacement computation`() async throws {
            let cache = Cache<String, Int>()
            let producerStarted = Async.Gate()
            let releaseProducer = Async.Gate()
            let waiterEnqueued = Async.Gate()
            cache.setValue(0, for: "record")

            // The first expired reader atomically removes the stale ready value.
            let firstRemoval = cache.removeValue(for: "record") { $0 == 0 }
            #expect(firstRemoval == 0)

            // A replacement begins and remains in flight while the second expired
            // reader attempts its own conditional removal.
            let producer = Task {
                try await cache.value(for: "record") {
                    _ = producerStarted.open()
                    await releaseProducer.wait()
                    return 42
                }
            }
            await producerStarted.wait()

            let secondRemoval = cache.removeValue(for: "record") { _ in true }
            #expect(secondRemoval == nil)

            // The public cache surface deliberately does not expose entry state.
            // This debug-only hook acknowledges the exact enqueue event, so the
            // release below cannot race a scheduler-polling budget.
            cache._storage.testing.waiterEnqueued.withLock { $0 = { _ = waiterEnqueued.open() } }
            let waiter = Task {
                try await cache.value(for: "record") { -1 }
            }
            await waiterEnqueued.wait()
            #expect(Self.isComputing(in: cache, for: "record"))

            _ = releaseProducer.open()

            #expect(try await producer.value == 42)
            #expect(try await waiter.value == 42)
            #expect(cache.cachedValue(for: "record") == 42)
        }
    #endif

    #if DEBUG
        // MARK: F-002 - Waiter cancellation must not wait for publish

        @Test
        func `cancelling a waiter while compute is stuck resumes it promptly`() async throws {
            let cache = Cache<String, Int>()
            let producerStarted = Async.Gate()
            let releaseProducer = Async.Gate()
            let waiterOutcome = Outcome<Int>()
            let waiterEnqueued = Async.Gate()
            let waiterCompleted = Async.Gate()

            // The producer becomes the "computing" party and then parks until
            // the test explicitly releases it at teardown - simulating a
            // compute closure that hangs.
            let producer = Task {
                do throws(Cache<String, Int>.Error) {
                    _ = try await cache.value(for: "stuck") {
                        _ = producerStarted.open()
                        await releaseProducer.wait()
                        return 0
                    }
                } catch {
                    // Discarded: this producer's own error path isn't under test here.
                }
            }

            await producerStarted.wait()

            // This second request for the same key becomes a waiter (the entry
            // is already `.computing`). It records its outcome the moment it
            // resumes.
            cache._storage.testing.waiterEnqueued.withLock { $0 = { _ = waiterEnqueued.open() } }
            let waiter = Task {
                let outcome: Outcome<Int>.Terminal
                do throws(Cache<String, Int>.Error) {
                    let value = try await cache.value(for: "stuck") { 0 }
                    outcome = .succeeded(value)
                } catch {
                    outcome = .threw(error)
                }
                await waiterOutcome.record(outcome)
                _ = waiterCompleted.open()
            }

            await waiterEnqueued.wait()
            #expect(Self.isComputing(in: cache, for: "stuck"))

            waiter.cancel()

            // The waiter opens this gate only after recording its terminal result.
            // This is a causal cancellation/resumption acknowledgement, not a
            // scheduler or wall-clock polling budget.
            await waiterCompleted.wait()
            let observed = await waiterOutcome.value

            switch observed {
            case .threw(let error):
                if let cacheError = error as? Cache<String, Int>.Error {
                    guard case .cancelled = cacheError else {
                        Issue.record("expected .cancelled, got \(cacheError)")
                        break
                    }
                } else {
                    Issue.record("expected a Cache.Error, got \(type(of: error)): \(error)")
                }

            case .succeeded(let value):
                Issue.record(
                    "expected cancellation to resume the waiter with .cancelled, but it succeeded with \(value)"
                )

            case nil:
                Issue.record("waiter completed without recording a terminal result")
            }

            // Teardown: release the parked producer and let both tasks finish.
            _ = releaseProducer.open()
            _ = await producer.value
            _ = await waiter.value
        }
    #endif

    // MARK: F-001 - Failed computations must not poison later attempts

    @Test
    func `a failed computation does not poison the next request`() async throws {
        struct Fault: Swift.Error, Equatable {
            let code: Int
        }

        let cache = Cache<String, Int>()

        // First attempt fails; the caller receives the compute error.
        do throws(Cache<String, Int>.Error) {
            _ = try await cache.value(for: "flaky") { throw Fault(code: 7) }
            Issue.record("expected the first computation's error to propagate")
        } catch {
            guard case .computeFailed(let underlying) = error,
                let computeError = underlying as? Fault
            else {
                Issue.record("expected .computeFailed(Fault), got \(error)")
                return
            }
            #expect(computeError == Fault(code: 7))
        }

        // The failure must not be cached: per the README's non-poisoning
        // promise ("a failed computation does not poison later attempts"),
        // the next request for the same key recomputes.
        let recovered = try await cache.value(for: "flaky") { 42 }
        #expect(recovered == 42)

        // And the recomputed value is now cached normally.
        #expect(cache.cachedValue(for: "flaky") == 42)
    }
}
