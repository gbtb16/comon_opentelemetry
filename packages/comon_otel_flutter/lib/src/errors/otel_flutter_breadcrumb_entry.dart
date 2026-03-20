/// Single breadcrumb entry captured by Flutter instrumentation.
final class OtelFlutterBreadcrumbEntry {
  /// Creates a breadcrumb entry.
  const OtelFlutterBreadcrumbEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.attributes = const <String, Object>{},
  });

  /// Timestamp of the breadcrumb.
  final DateTime timestamp;

  /// Breadcrumb category.
  final String category;

  /// Human-readable breadcrumb message.
  final String message;

  /// Structured breadcrumb attributes.
  final Map<String, Object> attributes;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' ')
      ..write(category)
      ..write(' ')
      ..write(message);
    if (attributes.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(
          attributes.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join(', '),
        );
    }
    return buffer.toString();
  }
}
