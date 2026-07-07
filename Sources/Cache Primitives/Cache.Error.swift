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
    /// Errors that can occur during cache operations.
    ///
    /// ## Error Types
    ///
    /// - `computeFailed`: The computation closure threw an error
    /// - `cancelled`: The waiting task was cancelled
    public enum Error: Swift.Error, Sendable {
        // reason: structural bottom-out — `Cache` is not generic over the
        // compute closure's error type, so the underlying error is boxed as
        // `any Swift.Error` by design; making this concrete would require a
        // generic-error redesign of the whole Cache/Action/Entry.State chain.
        // swiftlint:disable no_any_protocol_existential
        /// The computation closure threw an error.
        ///
        /// Contains the underlying error from the compute closure.
        case computeFailed(any Swift.Error)
        // swiftlint:enable no_any_protocol_existential

        /// The task was cancelled while waiting for computation.
        case cancelled
    }
}

// MARK: - CustomStringConvertible

extension Cache.Error: CustomStringConvertible {
    /// A human-readable description of this cache error.
    public var description: String {
        switch self {
        case .computeFailed(let error):
            "Cache.Error.computeFailed(\(error))"

        case .cancelled:
            "Cache.Error.cancelled"
        }
    }
}
