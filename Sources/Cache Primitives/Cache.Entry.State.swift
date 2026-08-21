extension Cache.Entry {

    @usableFromInline

    enum State: @unchecked Sendable {

        case empty

        case computing(Waiters)

        case ready(Value)

        case failed(any Swift.Error)

    }
}
