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

public import Effect_Primitives

extension Cache {
    /// Effect performed when a cache entry is evicted.
    ///
    /// This effect notifies handlers when an entry is removed from the cache,
    /// enabling cleanup, logging, or cascading invalidation.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// struct EvictionLogger: Effect.Handler.Protocol {
    ///     typealias Handled = Cache<String, User>.Evict
    ///
    ///     func handle(
    ///         _ effect: Handled,
    ///         continuation: consuming Effect.Continuation.One<Void, Never>
    ///     ) async {
    ///         print("Evicted \(effect.key): \(effect.reason)")
    ///         await continuation.resume()
    ///     }
    /// }
    /// ```
    ///
    /// - Note: Uses `_Value` to reference the outer `Cache.Value` generic
    ///   parameter, which is shadowed by `typealias Value = Void` required
    ///   by `Effect.Protocol` conformance. See
    ///   `Experiments/cache-effect-type-nesting/` for 8 approaches tested
    ///   (Swift 6.2.4) and why this workaround is necessary.
    public struct Evict: Effect.`Protocol`, Sendable {
        /// The effect's argument type: the evicted key, value, and reason.
        public typealias Arguments = (key: Key, value: _Value, reason: Reason)

        /// The effect's produced value type — none; eviction is fire-and-forget.
        public typealias Value = Void

        /// The effect's failure type — none; eviction cannot fail.
        public typealias Failure = Never

        /// The key that was evicted.
        public let key: Key

        /// The value that was evicted.
        public let value: _Value

        /// The reason for eviction.
        public let reason: Reason

        /// The arguments for this effect.
        public var arguments: (key: Key, value: _Value, reason: Reason) {
            (key, value, reason)
        }

        /// Creates an eviction effect.
        ///
        /// - Parameters:
        ///   - key: The key that was evicted.
        ///   - value: The value that was evicted.
        ///   - reason: The reason for eviction.
        @inlinable
        public init(key: Key, value: _Value, reason: Reason) {
            self.key = key
            self.value = value
            self.reason = reason
        }

        /// The reason a cache entry was evicted.
        public enum Reason: Sendable, Equatable {
            /// Entry was explicitly removed via `removeValue(for:)`.
            case explicit

            /// Entry was removed due to capacity constraints.
            case capacityLimit

            /// Entry expired based on TTL policy.
            case expired

            /// Entry was replaced by a new value.
            case replaced

            /// Cache was cleared via `removeAll()`.
            case cleared
        }
    }
}
