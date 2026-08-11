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

// MARK: - Test Error

private struct Fault: Swift.Error, Sendable, Equatable {
    let code: Int
}

// MARK: - Tests

@Suite
struct `Cache.Compute Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    @Test
    func `effect stores key as arguments`() {
        let effect = Cache<String, Int, Fault>.Compute(key: "test-key")

        #expect(effect.key == "test-key")
        #expect(effect.arguments == "test-key")
    }

    @Test
    func `effect with different key types`() {
        let stringEffect = Cache<String, Int, Fault>.Compute(key: "key")
        #expect(stringEffect.key == "key")

        let intEffect = Cache<Int, String, Fault>.Compute(key: 42)
        #expect(intEffect.key == 42)

        struct Tag: Hashable, Sendable {
            let id: Int
            let name: String
        }
        let customEffect = Cache<Tag, Bool, Fault>.Compute(
            key: Tag(id: 1, name: "test")
        )
        #expect(customEffect.key == Tag(id: 1, name: "test"))
    }

    @Test
    func `effect conforms to Effect.Protocol`() {
        let effect = Cache<String, Int, Fault>.Compute(key: "key")

        // Verify associated types
        let _: String = effect.arguments
        let _: Cache<String, Int, Fault>.Compute.Value.Type = Int.self
        let _: Cache<String, Int, Fault>.Compute.Failure.Type = Fault.self
    }
}
