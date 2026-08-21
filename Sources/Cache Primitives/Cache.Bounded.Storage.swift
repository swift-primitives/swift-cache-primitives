public import Async_Mutex_Primitives
import Async_Primitives
public import Ownership_Primitives

extension Cache.Bounded {

    @usableFromInline
    struct Storage: Sendable {
        @usableFromInline
        let _storage: Ownership.Mutable<Async.Mutex<State>>.Unchecked

        @inlinable
        package init(capacity: Int) {
            self._storage = Ownership.Mutable.Unchecked(Async.Mutex(State(capacity: capacity)))
        }
    }
}

extension Cache.Bounded.Storage {
    @inlinable
    package func withLock<T: ~Copyable, E: Swift.Error>(
        _ body: (inout sending Cache.Bounded.State) throws(E) -> sending T
    ) throws(E) -> sending T {
        try _storage.mutable.value.withLock(body)
    }
}
