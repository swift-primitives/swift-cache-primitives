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

extension Cache {
    /// A synchronous, capacity-bounded key-value cache.
    ///
    /// `Cache.Bounded` stores at most `capacity` entries. Inserting a new key
    /// while the cache is full evicts the oldest entry first (insertion
    /// order — first inserted, first evicted). Replacing the value for an
    /// existing key never evicts and never changes the key's insertion-order
    /// position.
    ///
    /// ## Design
    ///
    /// Unlike ``Cache`` (async compute-once with in-flight coordination),
    /// `Cache.Bounded` is a plain synchronous store: no compute closures,
    /// no waiters, no failure states. It is the sibling family member for
    /// "hold at most N entries" ([DS-027].2 — distinct observable law:
    /// evict-on-capacity, never throws).
    ///
    /// ## Thread Safety
    ///
    /// All operations are internally synchronized via mutex, matching the
    /// reference-storage idiom of ``Cache``. The type is `Sendable`; a `let`
    /// binding can be mutated from any isolation.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let cache = Cache<String, Int>.Bounded(capacity: 2)
    /// cache.insert(1, forKey: "a")
    /// cache.insert(2, forKey: "b")
    /// cache.insert(3, forKey: "c")   // evicts "a" (oldest)
    /// cache.getValue(forKey: "a")    // nil
    /// ```
    public struct Bounded: Sendable {
        @usableFromInline
        let _storage: Storage

        /// Creates an empty bounded cache.
        ///
        /// - Parameter capacity: The maximum number of entries the cache
        ///   holds. Must be positive.
        @inlinable
        public init(capacity: Int) {
            precondition(capacity > 0, "Cache.Bounded capacity must be positive")
            self._storage = Storage(capacity: capacity)
        }
    }
}

// MARK: - Insertion

extension Cache.Bounded {
    /// Inserts or replaces the value for a key, evicting the oldest entry
    /// when the insertion would exceed capacity.
    ///
    /// - If `key` is already present, its value is replaced in place: the
    ///   entry keeps its insertion-order position and nothing is evicted.
    /// - If `key` is new and the cache is at capacity, the oldest entry
    ///   (first inserted) is evicted to make room.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The key to store it under.
    @inlinable
    public func insert(_ value: Value, forKey key: Key) {
        _storage.withLock { state in
            if state.entries.updateValue(value, forKey: key) != nil {
                // Replacement: order position and count unchanged.
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

// MARK: - Read Operations

extension Cache.Bounded {
    /// Gets the cached value for a key, if present.
    ///
    /// Reading does not affect eviction order (insertion order, not recency,
    /// determines eviction).
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The cached value, or `nil` if not present.
    @inlinable
    public func getValue(forKey key: Key) -> Value? {
        _storage.withLock { state in
            state.entries[key]
        }
    }

    /// The number of cached entries.
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

// MARK: - Removal

extension Cache.Bounded {
    /// Removes the cached value for a key.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: The removed value, or `nil` if the key was not present.
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

    /// Removes all cached entries.
    @inlinable
    public func removeAll() {
        _storage.withLock { state in
            state.entries.removeAll()
            state.order.removeAll()
        }
    }
}

// MARK: - Filtering

extension Cache.Bounded {
    /// Retains only the entries satisfying the predicate.
    ///
    /// Entries for which `isIncluded` returns `false` are removed. Retained
    /// entries keep their relative insertion order (and thus their eviction
    /// order).
    ///
    /// - Parameter isIncluded: Predicate over `(key, value)`; return `true`
    ///   to keep the entry.
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
