import Testing

@testable import Cache_Primitives

private struct Fault: Swift.Error, Sendable, Equatable {
    let code: Int
}

@Suite
struct `Cache.Compute Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `effect stores key as arguments`() {
        let effect = Cache<String, Int>.Compute<Fault>(key: "test-key")

        #expect(effect.key == "test-key")
        #expect(effect.arguments == "test-key")
    }

    @Test
    func `effect with different key types`() {
        let stringEffect = Cache<String, Int>.Compute<Fault>(key: "key")
        #expect(stringEffect.key == "key")

        let intEffect = Cache<Int, String>.Compute<Fault>(key: 42)
        #expect(intEffect.key == 42)

        struct Tag: Hashable, Sendable {
            let id: Int
            let name: String
        }
        let customEffect = Cache<Tag, Bool>.Compute<Fault>(
            key: Tag(id: 1, name: "test")
        )
        #expect(customEffect.key == Tag(id: 1, name: "test"))
    }

    @Test
    func `effect conforms to Effect.Protocol`() {
        let effect = Cache<String, Int>.Compute<Fault>(key: "key")

        let _: String = effect.arguments
        let _: Cache<String, Int>.Compute<Fault>.Value.Type = Int.self
        let _: Cache<String, Int>.Compute<Fault>.Failure.Type = Fault.self
    }
}
