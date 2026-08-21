extension Cache {

    @usableFromInline
    struct State {
        @usableFromInline
        var entries: [Key: Entry]

        @inlinable
        package init() {
            self.entries = [:]
        }
    }
}
