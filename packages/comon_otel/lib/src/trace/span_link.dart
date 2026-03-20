import 'span_context.dart';

/// Link from a span to another related span context.
final class SpanLink {
  /// Creates a span link.
  SpanLink({required this.context, Map<String, Object>? attributes})
    : attributes = Map<String, Object>.unmodifiable(
        attributes ?? const <String, Object>{},
      );

  /// Linked span context.
  final SpanContext context;

  /// Immutable attributes associated with the link.
  final Map<String, Object> attributes;
}
