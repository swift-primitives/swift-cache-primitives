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

// MARK: - Tests

@Suite
struct `Cache.Bounded Tests` {

    // MARK: Insert / get

    @Test
    func `insert then getValue returns the value`() {
        let cache = Cache<String, Int>.Bounded(capacity: 4)
        cache.insert(42, forKey: "answer")

        #expect(cache.getValue(forKey: "answer") == 42)
        #expect(cache.count == 1)
        #expect(cache.isEmpty == false)
    }

    @Test
    func `getValue for a missing key returns nil`() {
        let cache = Cache<String, Int>.Bounded(capacity: 4)

        #expect(cache.getValue(forKey: "missing") == nil)
        #expect(cache.isEmpty)
    }

    // MARK: Eviction law

    @Test
    func `insert beyond capacity evicts the oldest entry`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(3, forKey: "c")

        #expect(cache.getValue(forKey: "a") == nil)
        #expect(cache.getValue(forKey: "b") == 2)
        #expect(cache.getValue(forKey: "c") == 3)
        #expect(cache.count == 2)
    }

    @Test
    func `count never exceeds capacity`() {
        let cache = Cache<Int, Int>.Bounded(capacity: 3)
        for i in 0..<10 {
            cache.insert(i, forKey: i)
            #expect(cache.count <= 3)
        }
        #expect(cache.count == 3)
        // The three newest survive.
        #expect(cache.getValue(forKey: 7) == 7)
        #expect(cache.getValue(forKey: 8) == 8)
        #expect(cache.getValue(forKey: 9) == 9)
        #expect(cache.getValue(forKey: 6) == nil)
    }

    @Test
    func `capacity one always keeps the newest entry`() {
        let cache = Cache<String, Int>.Bounded(capacity: 1)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")

        #expect(cache.getValue(forKey: "a") == nil)
        #expect(cache.getValue(forKey: "b") == 2)
        #expect(cache.count == 1)
    }

    // MARK: Replacement law

    @Test
    func `replacing an existing key does not evict and does not grow`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(10, forKey: "a")

        #expect(cache.count == 2)
        #expect(cache.getValue(forKey: "a") == 10)
        #expect(cache.getValue(forKey: "b") == 2)
    }

    @Test
    func `replacement keeps the original insertion-order position`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(10, forKey: "a")  // replaces; "a" remains oldest
        cache.insert(3, forKey: "c")  // evicts "a", not "b"

        #expect(cache.getValue(forKey: "a") == nil)
        #expect(cache.getValue(forKey: "b") == 2)
        #expect(cache.getValue(forKey: "c") == 3)
    }

    // MARK: Removal

    @Test
    func `removeValue returns the removed value and frees a slot`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")

        #expect(cache.removeValue(forKey: "b") == 2)
        #expect(cache.count == 1)

        // The freed slot means this insert must NOT evict "a".
        cache.insert(3, forKey: "c")
        #expect(cache.getValue(forKey: "a") == 1)
        #expect(cache.getValue(forKey: "c") == 3)
        #expect(cache.count == 2)
    }

    @Test
    func `removeValue for a missing key returns nil`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")

        #expect(cache.removeValue(forKey: "missing") == nil)
        #expect(cache.count == 1)
    }

    @Test
    func `removeAll empties the cache`() {
        let cache = Cache<String, Int>.Bounded(capacity: 3)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")

        cache.removeAll()

        #expect(cache.isEmpty)
        #expect(cache.count == 0)
        #expect(cache.getValue(forKey: "a") == nil)

        // Cache remains usable after clearing.
        cache.insert(3, forKey: "c")
        #expect(cache.getValue(forKey: "c") == 3)
    }

    // MARK: Filtering

    @Test
    func `filter retains only matching entries`() {
        let cache = Cache<String, Int>.Bounded(capacity: 4)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(3, forKey: "c")

        cache.filter { _, value in value % 2 == 1 }

        #expect(cache.getValue(forKey: "a") == 1)
        #expect(cache.getValue(forKey: "b") == nil)
        #expect(cache.getValue(forKey: "c") == 3)
        #expect(cache.count == 2)
    }

    @Test
    func `filter preserves eviction order of retained entries`() {
        let cache = Cache<String, Int>.Bounded(capacity: 3)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")
        cache.insert(3, forKey: "c")

        cache.filter { key, _ in key != "a" }  // drops "a"; order is now b, c
        cache.insert(4, forKey: "d")  // count 3, no eviction
        cache.insert(5, forKey: "e")  // evicts "b" (oldest retained)

        #expect(cache.getValue(forKey: "b") == nil)
        #expect(cache.getValue(forKey: "c") == 3)
        #expect(cache.getValue(forKey: "d") == 4)
        #expect(cache.getValue(forKey: "e") == 5)
        #expect(cache.count == 3)
    }

    @Test
    func `filter that keeps everything changes nothing`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")

        cache.filter { _, _ in true }

        #expect(cache.count == 2)
        #expect(cache.getValue(forKey: "a") == 1)
        #expect(cache.getValue(forKey: "b") == 2)
    }

    // MARK: Capacity contract

    @Test
    func `zero capacity traps`() async {
        await #expect(processExitsWith: .failure) {
            _ = Cache<String, Int>.Bounded(capacity: 0)
        }
    }

    @Test
    func `negative capacity traps`() async {
        await #expect(processExitsWith: .failure) {
            _ = Cache<String, Int>.Bounded(capacity: -1)
        }
    }

    // MARK: Concurrency

    @Test
    func `concurrent inserts across distinct keys never exceed capacity`() async {
        let capacity = 8
        let cache = Cache<Int, Int>.Bounded(capacity: capacity)

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<16 {
                group.addTask {
                    for iteration in 0..<250 {
                        cache.insert(iteration, forKey: worker * 1000 + iteration)
                    }
                }
            }
        }

        #expect(cache.count == capacity)
        #expect(cache.isEmpty == false)
    }

    @Test
    func `concurrent mixed reads writes and removals stay consistent`() async {
        let cache = Cache<Int, Int>.Bounded(capacity: 32)

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<4 {
                group.addTask {
                    for iteration in 0..<500 {
                        cache.insert(worker, forKey: iteration % 64)
                    }
                }
            }
            for _ in 0..<4 {
                group.addTask {
                    for iteration in 0..<500 {
                        if let value = cache.getValue(forKey: iteration % 64) {
                            precondition(
                                (0..<4).contains(value),
                                "a read must observe a value some writer inserted"
                            )
                        }
                    }
                }
            }
            for _ in 0..<2 {
                group.addTask {
                    for iteration in 0..<500 {
                        cache.removeValue(forKey: iteration % 64)
                    }
                }
            }
        }

        #expect(cache.count <= 32)
    }

    @Test
    func `concurrent replacement of one key under contention keeps a single entry`() async {
        let cache = Cache<String, Int>.Bounded(capacity: 4)

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for _ in 0..<500 {
                        cache.insert(worker, forKey: "contended")
                    }
                }
            }
        }

        #expect(cache.count == 1)
        let survivor = cache.getValue(forKey: "contended")
        #expect(survivor != nil)
        if let survivor {
            #expect((0..<8).contains(survivor))
        }
    }
}
