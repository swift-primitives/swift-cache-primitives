public import Effect_Primitives

extension Cache {

    public struct Compute<E: Swift.Error>: Effect.`Protocol` {

        public let key: Key

        @inlinable
        public init(key: Key) {
            self.key = key
        }
    }
}

extension Cache.Compute {

    public typealias Arguments = Key

    public typealias Value = Cache._Value

    public typealias Failure = E

    public var arguments: Key { key }
}
