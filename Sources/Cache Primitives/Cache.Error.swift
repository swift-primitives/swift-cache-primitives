extension Cache {

    public enum Error: Swift.Error, Sendable {

        case computeFailed(any Swift.Error)

        case cancelled
    }
}

extension Cache.Error: CustomStringConvertible {

    public var description: String {
        switch self {
        case .computeFailed(let error):
            "Cache.Error.computeFailed(\(error))"

        case .cancelled:
            "Cache.Error.cancelled"
        }
    }
}
