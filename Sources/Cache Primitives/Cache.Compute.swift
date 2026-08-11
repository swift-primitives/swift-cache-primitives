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
    ///     typealias Handled = Cache<String, User, Database.Error>.Compute
    ///
    ///     let database: Database
    ///
    ///     func handle(
    ///         _ effect: Handled,
    ///         continuation: consuming Effect.Continuation.One<User, Database.Error>
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
    /// - Note: Uses `_Value` and `_Failure` to satisfy the effect protocol
    ///   without shadowing the corresponding outer cache parameters.
    public struct Compute: Effect.`Protocol` {
        /// The key for which to compute a value.
        public let key: Key

        /// Creates a compute effect for the given key.
        ///
        /// - Parameter key: The key for which to compute a value.
        @inlinable
        public init(key: Key) {
            self.key = key
        }
    }
}

extension Cache.Compute {
    /// The effect's argument type: the cache key to compute a value for.
    public typealias Arguments = Key

    /// The effect's produced value type.
    public typealias Value = Cache._Value

    /// The effect's failure type.
    public typealias Failure = Cache._Failure

    /// The arguments for this effect (the key).
    public var arguments: Key { key }
}
