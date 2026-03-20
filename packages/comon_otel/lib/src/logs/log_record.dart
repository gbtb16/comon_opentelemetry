import '../context/otel_context.dart';
import '../core/resource.dart';
import '../trace/span_id.dart';
import '../trace/span_context.dart';
import '../trace/trace_flags.dart';
import '../trace/trace_id.dart';
import '../trace/trace_state.dart';
import 'severity.dart';

/// Immutable OpenTelemetry log record.
final class LogRecord {
  /// Creates a log record.
  const LogRecord({
    required this.timestamp,
    required this.severity,
    required this.body,
    required this.resource,
    this.observedTimestamp,
    this.spanContext,
    this.severityText,
    this.attributes = const <String, Object>{},
    this.loggerName,
  });

  /// Creates a log record using the current context's span, if present.
  factory LogRecord.current({
    DateTime? timestamp,
    DateTime? observedTimestamp,
    required SeverityNumber severity,
    String? severityText,
    required String body,
    Map<String, Object> attributes = const <String, Object>{},
    required Resource resource,
    String? loggerName,
  }) {
    return LogRecord(
      timestamp: timestamp ?? DateTime.now().toUtc(),
      observedTimestamp: observedTimestamp ?? DateTime.now().toUtc(),
      severity: severity,
      severityText: severityText,
      body: body,
      attributes: attributes,
      resource: resource,
      spanContext: OtelContext.current.spanContext,
      loggerName: loggerName,
    );
  }

  /// Creates a log record from explicit typed trace identifiers.
  factory LogRecord.typed({
    required DateTime timestamp,
    DateTime? observedTimestamp,
    required SeverityNumber severity,
    String? severityText,
    required String body,
    Map<String, Object> attributes = const <String, Object>{},
    required Resource resource,
    required TraceId traceId,
    required SpanId spanId,
    TraceFlags traceFlags = TraceFlags.none,
    TraceState? traceState,
    bool isRemote = false,
    String? loggerName,
  }) {
    return LogRecord(
      timestamp: timestamp,
      observedTimestamp: observedTimestamp,
      severity: severity,
      severityText: severityText,
      body: body,
      attributes: attributes,
      resource: resource,
      spanContext: isRemote
          ? SpanContext.remote(
              traceId: traceId,
              spanId: spanId,
              traceFlags: traceFlags,
              traceState: traceState,
            )
          : SpanContext.local(
              traceId: traceId,
              spanId: spanId,
              traceFlags: traceFlags,
              traceState: traceState,
            ),
      loggerName: loggerName,
    );
  }

  /// Event time of the log record.
  final DateTime timestamp;

  /// Time when the log was observed, if different from [timestamp].
  final DateTime? observedTimestamp;

  /// Associated span context, when available.
  final SpanContext? spanContext;

  /// Numeric severity.
  final SeverityNumber severity;

  /// Text severity label.
  final String? severityText;

  /// Human-readable log body.
  final String body;

  /// Structured attributes attached to the log record.
  final Map<String, Object> attributes;

  /// Resource attached to the log record.
  final Resource resource;

  /// Logger name that emitted the record.
  final String? loggerName;

  /// Trace ID associated with the log record, if any.
  String? get traceId => spanContext?.traceId;

  /// Span ID associated with the log record, if any.
  String? get spanId => spanContext?.spanId;

  /// Whether the associated span context is sampled, if any.
  bool? get sampled => spanContext?.sampled;

  /// Serialized tracestate from the associated span context, if any.
  String? get traceState => spanContext?.traceState;

  /// Typed trace ID associated with the log record, if any.
  TraceId? get traceIdValue => spanContext?.traceIdValue;

  /// Typed span ID associated with the log record, if any.
  SpanId? get spanIdValue => spanContext?.spanIdValue;

  /// Trace flags associated with the log record, if any.
  TraceFlags? get traceFlags => spanContext?.traceFlags;

  /// Typed tracestate associated with the log record, if any.
  TraceState? get traceStateValue => spanContext?.traceStateValue;
}
