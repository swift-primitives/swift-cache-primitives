public import Effect_Primitives

extension Cache {

    public struct Evict: Effect.`Protocol`, Sendable {

        public let key: Key

        public let value: _Value

        public let reason: Reason

        @inlinable
        public init(key: Key, value: _Value, reason: Reason) {
            self.key = key
            self.value = value
            self.reason = reason
        }
    }
}

extension Cache.Evict {

    public typealias Arguments = (key: Key, value: Cache._Value, reason: Reason)

    public typealias Value = Void

    public typealias Failure = Never

    public var arguments: (key: Key, value: Cache._Value, reason: Reason) {
        (key, value, reason)
    }
}
