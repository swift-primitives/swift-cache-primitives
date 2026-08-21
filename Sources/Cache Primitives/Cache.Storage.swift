public import Async_Mutex_Primitives
public import Ownership_Primitives

#if DEBUG
    internal import Synchronization
#endif

extension Cache {

    @usableFromInline
    struct Storage: Sendable {
        @usableFromInline
        let _storage: Ownership.Mutable<Async.Mutex<State>>.Unchecked

        #if DEBUG

            final class Testing: @unchecked Sendable {

                let waiterEnqueued = Mutex<(@Sendable () -> Void)?>(nil)
            }

            let testing = Testing()
        #endif

        @inlinable
        package init() {
            self._storage = Ownership.Mutable.Unchecked(Async.Mutex(State()))
        }
    }
}

extension Cache.Storage {
    @inlinable
    package func withLock<T: ~Copyable, E: Swift.Error>(
        _ body: (inout sending Cache.State) throws(E) -> sending T
    ) throws(E) -> sending T {
        try _storage.mutable.value.withLock(body)
    }
}
