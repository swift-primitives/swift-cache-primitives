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

extension Cache.Evict {
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
