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

extension Cache.Entry.Waiters {
    /// The terminal outcome delivered from one producer to its waiters.
    @usableFromInline
    enum Outcome: Sendable {
        case success(Value)
        case failure(Failure)
        case cancelled
    }
}
