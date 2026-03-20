/// Metric instrument that records a distribution of values.
abstract interface class Histogram<T extends num> {
  /// Records a measurement into the histogram.
  void record(T value, {Map<String, Object>? attributes});
}
