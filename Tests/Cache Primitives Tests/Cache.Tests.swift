import Async_Primitives
import Synchronization
import Testing

@testable import Cache_Primitives

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

            let firstRemoval = cache.removeValue(for: "record") { $0 == 0 }
            #expect(firstRemoval == 0)

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

        @Test
        func `cancelling a waiter while compute is stuck resumes it promptly`() async throws {
            let cache = Cache<String, Int>()
            let producerStarted = Async.Gate()
            let releaseProducer = Async.Gate()
            let waiterOutcome = Outcome<Int>()
            let waiterEnqueued = Async.Gate()
            let waiterCompleted = Async.Gate()

            let producer = Task {
                do throws(Cache<String, Int>.Error) {
                    _ = try await cache.value(for: "stuck") {
                        _ = producerStarted.open()
                        await releaseProducer.wait()
                        return 0
                    }
                } catch {

                }
            }

            await producerStarted.wait()

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

            _ = releaseProducer.open()
            _ = await producer.value
            _ = await waiter.value
        }
    #endif

    @Test
    func `a failed computation does not poison the next request`() async throws {
        struct Fault: Swift.Error, Equatable {
            let code: Int
        }

        let cache = Cache<String, Int>()

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

        let recovered = try await cache.value(for: "flaky") { 42 }
        #expect(recovered == 42)

        #expect(cache.cachedValue(for: "flaky") == 42)
    }
}
