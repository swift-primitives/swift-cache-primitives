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

import Testing

@testable import Cache_Primitives

// MARK: - Test Support

/// A one-shot, awaitable gate for coordinating test tasks.
///
/// `wait()` suspends until `open()` is called (from any task); calling
/// `open()` after the gate is already open is a no-op. Used to make the
/// producer/waiter interleaving in the cancellation test deterministic
/// instead of relying on sleep-based guessing for the "producer has started
/// computing" edge.
private actor Gate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}

/// A box recording a task's terminal outcome, pollable from the test body.
///
/// The waiter task under test writes its outcome here the moment it
/// resumes; the test polls with a bounded deadline instead of awaiting the
/// task directly, so a pre-fix stranded waiter fails the test rather than
/// hanging it (the direct await would deadlock: the waiter cannot resume
/// until the producer publishes, and the producer is parked until teardown).
private actor Outcome<Value: Sendable> {
    enum Terminal {
        case succeeded(Value)
        case threw(any Swift.Error)
    }

    private var terminal: Terminal?

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

    // MARK: F-002 - Waiter cancellation must not wait for publish

    @Test
    func `cancelling a waiter while compute is stuck resumes it promptly`() async throws {
        let cache = Cache<String, Int>()
        let producerStarted = Gate()
        let releaseProducer = Gate()
        let waiterOutcome = Outcome<Int>()

        // The producer becomes the "computing" party and then parks until
        // the test explicitly releases it at teardown - simulating a
        // compute closure that hangs.
        let producer = Task {
            try? await cache.value(for: "stuck") {
                await producerStarted.open()
                await releaseProducer.wait()
                return 0
            }
        }

        await producerStarted.wait()

        // This second request for the same key becomes a waiter (the entry
        // is already `.computing`). It records its outcome the moment it
        // resumes.
        let waiter = Task {
            do {
                let value = try await cache.value(for: "stuck") { 0 }
                await waiterOutcome.record(.succeeded(value))
            } catch {
                await waiterOutcome.record(.threw(error))
            }
        }

        // Give the waiter task time to register itself in the entry's
        // waiter queue before cancelling (mirrors the cancellation-test
        // idiom used for `Async.Semaphore.wait()`).
        try? await Task.sleep(for: .milliseconds(50))
        waiter.cancel()

        // Poll for the waiter's resumption with a bounded deadline
        // (~5s). Pre-fix, a cancelled waiter is not resumed until the
        // producer publishes - which never happens here on its own, since
        // the producer is parked - so an unfixed build exhausts the
        // deadline and fails below instead of hanging the suite.
        var observed: Outcome<Int>.Terminal?
        for _ in 0..<200 {
            if let terminal = await waiterOutcome.value {
                observed = terminal
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

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
            Issue.record(
                "waiter was not resumed within 5s of cancellation - stranded until publish (F-002)"
            )
        }

        // Teardown: release the parked producer and let both tasks finish.
        await releaseProducer.open()
        _ = await producer.value
        _ = await waiter.value
    }

    // MARK: F-001 - Failed computations must not poison later attempts

    @Test
    func `a failed computation does not poison the next request`() async throws {
        struct ComputeError: Swift.Error, Equatable {
            let code: Int
        }

        let cache = Cache<String, Int>()

        // First attempt fails; the caller receives the compute error.
        do {
            _ = try await cache.value(for: "flaky") { throw ComputeError(code: 7) }
            Issue.record("expected the first computation's error to propagate")
        } catch {
            guard case .computeFailed(let underlying) = error,
                let computeError = underlying as? ComputeError
            else {
                Issue.record("expected .computeFailed(ComputeError), got \(error)")
                return
            }
            #expect(computeError == ComputeError(code: 7))
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
