extension Cache.Evict {

    public enum Reason: Sendable, Equatable {

        case explicit

        case capacityLimit

        case expired

        case replaced

        case cleared
    }
}
