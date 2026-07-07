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
    /// Effect performed when computing a new cache value.
    ///
    /// When a cache lookup misses, this effect is performed to request
    /// computation of the value. Handlers interpret this effect to provide
    /// the actual computation logic.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Define a handler for computation
    /// struct UserCacheHandler: Effect.Handler.Protocol {
    ///     typealias Handled = Cache<String, User>.Compute<any Error>
    ///
    ///     let database: Database
    ///
    ///     func handle(
    ///         _ effect: Handled,
    ///         continuation: consuming Effect.Continuation.One<User, any Error>
    ///     ) async {
    ///         do {
    ///             let user = try await database.fetch(id: effect.key)
    ///             await continuation.resume(returning: user)
    ///         } catch {
    ///             await continuation.resume(throwing: error)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Note: Uses `_Value` to satisfy `Effect.Protocol.Value` with the
    ///   outer `Cache.Value` generic parameter, which cannot be inferred
    ///   across the generic nesting boundary when `Compute` introduces
    ///   its own generic parameter `E`. See
    ///   `Experiments/cache-effect-type-nesting/` for 8 approaches tested
    ///   (Swift 6.2.4) and why this workaround is necessary.
    public struct Compute<E: Swift.Error>: Effect.`Protocol` {
        /// The effect's argument type: the cache key to compute a value for.
        public typealias Arguments = Key

        /// The effect's produced value type.
        public typealias Value = _Value

        /// The effect's failure type.
        public typealias Failure = E

        /// The key for which to compute a value.
        public let key: Key

        /// The arguments for this effect (the key).
        public var arguments: Key { key }

        /// Creates a compute effect for the given key.
        ///
        /// - Parameter key: The key for which to compute a value.
        @inlinable
        public init(key: Key) {
            self.key = key
        }
    }
}
