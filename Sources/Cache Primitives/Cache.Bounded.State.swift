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

extension Cache.Bounded {
    /// Internal synchronized state.
    @usableFromInline
    struct State {
        @usableFromInline
        var entries: [Key: Value]

        /// Insertion order of live keys, oldest first.
        ///
        /// Invariant: `order` contains exactly the keys of `entries`, each
        /// once, in insertion order. Eviction removes `order.first`.
        @usableFromInline
        var order: [Key]

        /// The maximum number of entries; enforced by `insert`.
        @usableFromInline
        let capacity: Int

        @inlinable
        package init(capacity: Int) {
            self.entries = [:]
            self.order = []
            self.capacity = capacity
        }
    }
}
