extension Cache {

    public struct Bounded: Sendable {
        @usableFromInline
        let _storage: Storage

        @inlinable
        public init(capacity: Int) {
            precondition(capacity > 0, "Cache.Bounded capacity must be positive")
            self._storage = Storage(capacity: capacity)
        }
    }
}

extension Cache.Bounded {

    @inlinable
    public func insert(_ value: Value, forKey key: Key) {
        _storage.withLock { state in
            if state.entries.updateValue(value, forKey: key) != nil {

                return
            }
            state.order.append(key)
            if state.entries.count > state.capacity {
                let oldest = state.order.removeFirst()
                state.entries.removeValue(forKey: oldest)
            }
        }
    }
}

extension Cache.Bounded {

    @inlinable
    public func getValue(forKey key: Key) -> Value? {
        _storage.withLock { state in
            state.entries[key]
        }
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

extension Cache.Bounded {

    @discardableResult
    @inlinable
    public func removeValue(forKey key: Key) -> Value? {
        _storage.withLock { state in
            guard let value = state.entries.removeValue(forKey: key) else {
                return nil
            }
            if let index = state.order.firstIndex(of: key) {
                state.order.remove(at: index)
            }
            return value
        }
    }

    @inlinable
    public func removeAll() {
        _storage.withLock { state in
            state.entries.removeAll()
            state.order.removeAll()
        }
    }
}

extension Cache.Bounded {

    @inlinable
    public func filter(_ isIncluded: (Key, Value) -> Bool) {
        _storage.withLock { state in
            var retained: [Key] = []
            retained.reserveCapacity(state.order.count)
            for key in state.order {
                guard let value = state.entries[key] else { continue }
                if isIncluded(key, value) {
                    retained.append(key)
                } else {
                    state.entries.removeValue(forKey: key)
                }
            }
            state.order = retained
        }
    }
}
