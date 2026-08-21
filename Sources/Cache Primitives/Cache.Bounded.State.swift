extension Cache.Bounded {

    @usableFromInline
    struct State {
        @usableFromInline
        var entries: [Key: Value]

        @usableFromInline
        var order: [Key]

        @usableFromInline
        let capacity: Int

        @inlinable
        package init(capacity: Int) {
            self.entries = [:]
            self.order = []
            self.capacity = capacity
        }
    }
}
