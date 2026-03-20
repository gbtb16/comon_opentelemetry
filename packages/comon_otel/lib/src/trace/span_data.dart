import '../core/instrumentation_scope.dart';
import '../core/resource.dart';
import 'span_id.dart';
import 'span_context.dart';
import 'span_event.dart';
import 'span_kind.dart';
import 'span_link.dart';
import 'span_status.dart';
import 'trace_flags.dart';
import 'trace_id.dart';
import 'trace_state.dart';

/// Immutable export-ready representation of a completed span.
final class SpanData {
  /// Creates a completed span payload.
  const SpanData({
    required this.name,
    required this.kind,
    required this.spanContext,
    required this.startTime,
    required this.endTime,
    required this.resource,
    this.parentSpanContext,
    this.status = SpanStatus.unset,
    this.statusDescription,
    this.attributes = const <String, Object>{},
    this.events = const <SpanEvent>[],
    this.links = const <SpanLink>[],
    this.droppedAttributesCount = 0,
    this.droppedEventsCount = 0,
    this.droppedLinksCount = 0,
    this.scope,
  });

  /// Span name as exported.
  final String name;

  /// Span kind as exported.
  final SpanKind kind;

  /// Context of the exported span itself.
  final SpanContext spanContext;

  /// Parent context, when present.
  final SpanContext? parentSpanContext;

  /// Exported span status.
  final SpanStatus status;

  /// Optional exported status description.
  final String? statusDescription;

  /// Span start timestamp.
  final DateTime startTime;

  /// Span end timestamp.
  final DateTime endTime;

  /// Resource associated with the exporting provider.
  final Resource resource;

  /// Exported span attributes.
  final Map<String, Object> attributes;

  /// Exported span events.
  final List<SpanEvent> events;

  /// Exported span links.
  final List<SpanLink> links;

  /// Number of dropped attributes caused by limits.
  final int droppedAttributesCount;

  /// Number of dropped events caused by limits.
  final int droppedEventsCount;

  /// Number of dropped links caused by limits.
  final int droppedLinksCount;

  /// Instrumentation scope that created the span.
  final InstrumentationScope? scope;

  /// Convenience accessor for the instrumentation scope name.
  String? get instrumentationScope => scope?.name;

  /// Trace ID of the exported span.
  String get traceId => spanContext.traceId;

  /// Span ID of the exported span.
  String get spanId => spanContext.spanId;

  /// Parent span ID when a parent context is present.
  String? get parentSpanId => parentSpanContext?.spanId;

  /// Whether the exported span was sampled.
  bool get sampled => spanContext.sampled;

  /// Serialized tracestate value when present.
  String? get traceState => spanContext.traceState;

  /// Typed trace ID for the exported span.
  TraceId get traceIdValue => spanContext.traceIdValue;

  /// Typed span ID for the exported span.
  SpanId get spanIdValue => spanContext.spanIdValue;

  /// Typed parent span ID when available.
  SpanId? get parentSpanIdValue => parentSpanContext?.spanIdValue;

  /// Trace flags associated with the exported span.
  TraceFlags get traceFlags => spanContext.traceFlags;

  /// Typed tracestate associated with the exported span context.
  TraceState? get traceStateValue => spanContext.traceStateValue;
}
