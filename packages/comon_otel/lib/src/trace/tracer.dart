import 'span.dart';
import '../context/otel_context.dart';
import '../core/instrumentation_scope.dart';
import 'span_context.dart';
import 'span_kind.dart';
import 'span_link.dart';
import 'tracer_provider.dart';

/// Creates spans for a specific instrumentation scope.
final class Tracer {
  /// Creates a tracer bound to [scope] and backed by [provider].
  Tracer({required TracerProvider provider, required this.scope})
    : _provider = provider;

  final TracerProvider _provider;

  /// The instrumentation scope reported on emitted spans.
  final InstrumentationScope scope;

  /// Name of the current instrumentation scope.
  String get name => scope.name;

  /// Optional version of the current instrumentation scope.
  String? get version => scope.version;

  /// Optional schema URL associated with the instrumentation scope.
  String? get schemaUrl => scope.schemaUrl;

  /// Additional instrumentation scope attributes attached to exported spans.
  Map<String, Object> get attributes => scope.attributes;

  /// Starts a new span using this tracer's instrumentation scope.
  Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object>? attributes,
    Span? parent,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    List<SpanLink>? links,
    DateTime? startTime,
  }) {
    return _provider.startSpan(
      instrumentationScope: scope,
      name: name,
      kind: kind,
      attributes: attributes,
      parent: parent,
      parentSnapshot: parentSnapshot,
      parentContext: parentContext,
      links: links,
      startTime: startTime,
    );
  }
}
