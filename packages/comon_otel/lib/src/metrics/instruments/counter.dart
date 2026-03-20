/// Monotonic metric instrument that accumulates positive increments.
abstract interface class Counter<T extends num> {
  /// Adds a value to the counter.
  void add(T value, {Map<String, Object>? attributes});
}
