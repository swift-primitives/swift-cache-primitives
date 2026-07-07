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
    /// Action to take after inspecting cache state.
    @usableFromInline
    enum Action {
        case returnValue(Value)

        // reason: structural bottom-out — mirrors Cache.Error.computeFailed;
        // `Cache` is not generic over the compute closure's error type.
        // swiftlint:disable no_any_protocol_existential
        case throwError(any Swift.Error)
        // swiftlint:enable no_any_protocol_existential

        case wait(Key, Entry)
        case compute(Key, Entry)
    }
}
