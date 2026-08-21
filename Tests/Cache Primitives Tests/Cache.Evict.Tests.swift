import Testing

@testable import Cache_Primitives

@Suite
struct `Cache.Evict Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `effect stores key, value, and reason`() {
        let effect = Cache<String, Int>.Evict(
            key: "test-key",
            value: 42,
            reason: .explicit
        )

        #expect(effect.key == "test-key")
        #expect(effect.value == 42)
        #expect(effect.reason == .explicit)
    }

    @Test
    func `arguments returns tuple`() {
        let effect = Cache<String, Int>.Evict(
            key: "key",
            value: 100,
            reason: .capacityLimit
        )

        let args = effect.arguments
        #expect(args.key == "key")
        #expect(args.value == 100)
        #expect(args.reason == .capacityLimit)
    }

    @Test
    func `all eviction reasons`() {
        let reasons: [Cache<String, Int>.Evict.Reason] = [
            .explicit,
            .capacityLimit,
            .expired,
            .replaced,
            .cleared,
        ]

        for reason in reasons {
            let effect = Cache<String, Int>.Evict(
                key: "key",
                value: 0,
                reason: reason
            )
            #expect(effect.reason == reason)
        }
    }

    @Test
    func `reason is Equatable`() {
        #expect(Cache<String, Int>.Evict.Reason.explicit == .explicit)
        #expect(Cache<String, Int>.Evict.Reason.explicit != .expired)
    }

    @Test
    func `effect has Never failure type`() {
        let _: Cache<String, Int>.Evict.Failure.Type = Never.self
    }

    @Test
    func `effect has Void value type`() {
        let _: Cache<String, Int>.Evict.Value.Type = Void.self
    }
}
