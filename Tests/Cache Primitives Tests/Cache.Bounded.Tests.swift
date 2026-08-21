import Testing

@testable import Cache_Primitives

@Suite
struct `Cache.Bounded Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

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
        (0..<10).forEach { i in
            cache.insert(i, forKey: i)
            #expect(cache.count <= 3)
        }
        #expect(cache.count == 3)

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
        cache.insert(10, forKey: "a")
        cache.insert(3, forKey: "c")

        #expect(cache.getValue(forKey: "a") == nil)
        #expect(cache.getValue(forKey: "b") == 2)
        #expect(cache.getValue(forKey: "c") == 3)
    }

    @Test
    func `removeValue returns the removed value and frees a slot`() {
        let cache = Cache<String, Int>.Bounded(capacity: 2)
        cache.insert(1, forKey: "a")
        cache.insert(2, forKey: "b")

        #expect(cache.removeValue(forKey: "b") == 2)
        #expect(cache.count == 1)

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

        cache.insert(3, forKey: "c")
        #expect(cache.getValue(forKey: "c") == 3)
    }

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

        cache.filter { key, _ in key != "a" }
        cache.insert(4, forKey: "d")
        cache.insert(5, forKey: "e")

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

    @Test
    func `concurrent inserts across distinct keys never exceed capacity`() async {
        let capacity = 8
        let cache = Cache<Int, Int>.Bounded(capacity: capacity)

        await withTaskGroup(of: Void.self) { group in
            (0..<16).forEach { worker in
                group.addTask {
                    (0..<250).forEach { iteration in
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
            (0..<4).forEach { worker in
                group.addTask {
                    (0..<500).forEach { iteration in
                        cache.insert(worker, forKey: iteration % 64)
                    }
                }
            }
            (0..<4).forEach { _ in
                group.addTask {
                    (0..<500).forEach { iteration in
                        if let value = cache.getValue(forKey: iteration % 64) {
                            precondition(
                                (0..<4).contains(value),
                                "a read must observe a value some writer inserted"
                            )
                        }
                    }
                }
            }
            (0..<2).forEach { _ in
                group.addTask {
                    (0..<500).forEach { iteration in
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
            (0..<8).forEach { worker in
                group.addTask {
                    (0..<500).forEach { _ in
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
