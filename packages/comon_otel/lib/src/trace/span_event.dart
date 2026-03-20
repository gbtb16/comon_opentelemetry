/// Time-stamped event recorded on a span.
final class SpanEvent {
  /// Creates a span event.
  const SpanEvent({
    required this.name,
    required this.timestamp,
    this.attributes = const <String, Object>{},
  });

  /// Event name.
  final String name;

  /// Event timestamp.
  final DateTime timestamp;

  /// Event attributes.
  final Map<String, Object> attributes;
}
