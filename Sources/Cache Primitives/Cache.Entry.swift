extension Cache {

    @usableFromInline

    final class Entry: @unchecked Sendable {
        @usableFromInline
        var state: State

        @inlinable
        package init() {
            self.state = .empty
        }

        @inlinable
        package init(state: State) {
            self.state = state
        }
    }
}
