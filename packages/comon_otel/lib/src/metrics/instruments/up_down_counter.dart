/// Metric instrument that accumulates positive and negative deltas.
abstract interface class UpDownCounter<T extends num> {
  /// Adds a delta to the up-down counter.
  void add(T value, {Map<String, Object>? attributes});
}
