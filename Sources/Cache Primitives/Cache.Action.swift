extension Cache {

    @usableFromInline
    enum Action {
        case returnValue(Value)

        case throwError(any Swift.Error)

        case wait(Key, Entry)
        case compute(Key, Entry)
    }
}
