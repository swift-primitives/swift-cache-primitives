# ``Cache_Primitives``

@Metadata {
    @DisplayName("Cache Primitives")
    @TitleHeading("Swift Primitives")
}

`Cache<Key, Value, Failure>` — a thread-safe, compute-if-absent async cache.
`value(for:compute:)` preserves the producer's concrete failure type and returns a cached
value or runs the async compute closure on a miss; concurrent callers for the same missing
key coalesce onto a single in-flight computation.

## Topics
