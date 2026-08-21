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

#if DEBUG
    internal import Synchronization
#endif

public struct Cache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    @usableFromInline
    let _storage: Storage

    @inlinable
    public init() {
        self._storage = Storage()
    }
}

extension Cache {

    public typealias _Value = Value
}

extension Cache {

    public func value(
        for key: Key,

        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value {

        let action = _storage.withLock { state -> Action in
            guard let entry = state.entries[key] else {

                let entry = Entry()
                entry.state = .computing(Entry.Waiters())
                state.entries[key] = entry
                return .compute(key, entry)
            }
            switch entry.state {
            case .ready(let value):

                return .returnValue(value)

            case .failed(let error):

                return .throwError(error)

            case .computing:

                return .wait(key, entry)

            case .empty:

                entry.state = .computing(Entry.Waiters())
                return .compute(key, entry)
            }
        }

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

extension Cache {

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

                            return Async.Waiter.Resumption {
                                continuation.resume(returning: .success(value))
                            }

                        case .failed(let error):

                            return Async.Waiter.Resumption {
                                continuation.resume(returning: .failure(error))
                            }

                        case .computing(let waiters):

                            if flag.cancelled {
                                return Async.Waiter.Resumption {
                                    continuation.resume(returning: .failure(CancellationError()))
                                }
                            }

                            let asyncContinuation = Async.Continuation<Entry.Waiters.Outcome> {
                                outcome in
                                continuation.resume(returning: outcome)
                            }
                            let waiterEntry = Async.Waiter.Entry(
                                continuation: asyncContinuation,
                                flag: flag
                            )
                            waiters.queue.enqueue(waiterEntry)
                            entry.state = .computing(waiters)
                            return nil

                        case .empty:

                            return Async.Waiter.Resumption {
                                continuation.resume(throwing: Error.cancelled)
                            }
                        }
                    }

                    if let resumption {
                        resumption.resume()
                    } else {
                        #if DEBUG
                            let waiterEnqueued = _storage.testing.waiterEnqueued.withLock { $0 }
                            waiterEnqueued?()
                        #endif
                    }
                }
            } onCancel: {

                if flag.cancel() {
                    Task { self.pumpCancelledWaiters(entry: entry) }
                }
            }
        } catch {
            throw .cancelled
        }

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

extension Cache {

    @usableFromInline
    func pumpCancelledWaiters(entry: Entry) {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { _ in
            guard case .computing(let waiters) = entry.state else {

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

        resumptions.drain { $0.resume() }
    }
}

extension Cache {

    @usableFromInline
    func computeAndPublish(
        key: Key,
        entry: Entry,

        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value {

        let result: Result<Value, any Swift.Error>

        do {
            let value = try await compute()
            result = .success(value)
        } catch {
            result = .failure(error)
        }

        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { state in
            guard case .computing(let waiters) = entry.state else {

                return
            }

            switch result {
            case .success(let value):
                entry.state = .ready(value)

            case .failure(let error):

                entry.state = .failed(error)
                if state.entries[key] === entry {
                    state.entries.removeValue(forKey: key)
                }
            }

            waiters.queue.drain { waiterEntry in

                if waiterEntry.flag.cancelled {
                    resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                } else {
                    resumptions.append(waiterEntry.resumption(with: result))
                }
            }
        }

        resumptions.drain { $0.resume() }

        switch result {
        case .success(let value):
            return value

        case .failure(let error):
            throw Error.computeFailed(error)
        }
    }
}

extension Cache {

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

    @inlinable
    public func contains(key: Key) -> Bool {
        cachedValue(for: key) != nil
    }

    @inlinable
    public var count: Int {
        _storage.withLock { state in
            state.entries.count
        }
    }

    @inlinable
    public var isEmpty: Bool {
        _storage.withLock { state in
            state.entries.isEmpty
        }
    }
}

extension Cache {

    @inlinable
    public func setValue(_ value: Value, for key: Key) {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { state in

            if let existingEntry = state.entries[key],
                case .computing(let waiters) = existingEntry.state
            {
                waiters.queue.drain { waiterEntry in
                    resumptions.append(waiterEntry.resumption(with: .success(value)))
                }
            }

            let entry = Entry()
            entry.state = .ready(value)
            state.entries[key] = entry
        }

        resumptions.drain { $0.resume() }
    }

    @discardableResult
    @inlinable
    public func removeValue(
        for key: Key,
        when condition: @Sendable (Value) -> Bool
    ) -> Value? {
        let captured = _storage.withLock { state -> (Entry, Value)? in
            guard let entry = state.entries[key],
                case .ready(let value) = entry.state
            else {
                return nil
            }

            return (entry, value)
        }

        guard let (entry, value) = captured, condition(value) else {
            return nil
        }

        return _storage.withLock { state in
            guard let current = state.entries[key],
                current === entry,
                case .ready = current.state
            else {
                return nil
            }

            state.entries.removeValue(forKey: key)
            return value
        }
    }

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

                waiters.queue.drain { waiterEntry in
                    resumptions.append(waiterEntry.resumption(with: .failure(CancellationError())))
                }
                return nil

            case .empty, .failed:
                return nil
            }
        }

        resumptions.drain { $0.resume() }

        return value
    }

    @inlinable
    public func removeAll() {
        var resumptions = __Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)
        _storage.withLock { state in
            for (_, entry) in state.entries {
                if case .computing(let waiters) = entry.state {
                    waiters.queue.drain { waiterEntry in
                        resumptions.append(
                            waiterEntry.resumption(with: .failure(CancellationError()))
                        )
                    }
                }
            }

            state.entries.removeAll()
        }

        resumptions.drain { $0.resume() }
    }
}

extension Cache {

    public func value(
        for key: Key,
        if shouldCompute: Bool,

        compute: @Sendable () async throws -> Value
    ) async throws(Self.Error) -> Value? {

        if let cached = cachedValue(for: key) {
            return cached
        }

        guard shouldCompute else {
            return nil
        }

        return try await value(for: key, compute: compute)
    }
}
