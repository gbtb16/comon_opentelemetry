import 'span_id.dart';
import 'trace_flags.dart';
import 'trace_id.dart';
import 'trace_state.dart';

/// Identifies a span within a trace and carries its propagation flags.
final class SpanContext {
  /// Creates a span context from string identifiers.
  const SpanContext({
    required String traceId,
    required String spanId,
    required bool sampled,
    this.isRemote = false,
    String? traceState,
  }) : _traceId = traceId,
       _spanId = spanId,
       traceFlags = sampled ? TraceFlags.sampled : TraceFlags.none,
       _traceState = traceState;

  /// Creates a span context from typed IDs and flags.
  SpanContext.typed({
    required TraceId traceId,
    required SpanId spanId,
    required this.traceFlags,
    this.isRemote = false,
    TraceState? traceState,
  }) : _traceId = traceId.hex,
       _spanId = spanId.hex,
       _traceState = traceState?.value;

  /// Creates a local span context for spans started in the current process.
  factory SpanContext.local({
    required TraceId traceId,
    required SpanId spanId,
    TraceFlags traceFlags = TraceFlags.none,
    TraceState? traceState,
  }) {
    return SpanContext.typed(
      traceId: traceId,
      spanId: spanId,
      traceFlags: traceFlags,
      traceState: traceState,
    );
  }

  /// Creates a remote span context extracted from inbound propagation data.
  factory SpanContext.remote({
    required TraceId traceId,
    required SpanId spanId,
    TraceFlags traceFlags = TraceFlags.none,
    TraceState? traceState,
  }) {
    return SpanContext.typed(
      traceId: traceId,
      spanId: spanId,
      traceFlags: traceFlags,
      traceState: traceState,
      isRemote: true,
    );
  }

  final String _traceId;
  final String _spanId;
  final TraceFlags traceFlags;
  final bool isRemote;
  final String? _traceState;

  /// Lowercase hexadecimal trace ID.
  String get traceId => _traceId.toLowerCase();

  /// Lowercase hexadecimal span ID.
  String get spanId => _spanId.toLowerCase();

  /// Whether the sampled bit is set on [traceFlags].
  bool get sampled => traceFlags.isSampled;

  /// Serialized tracestate value, if any.
  String? get traceState => _traceState;

  /// Typed trace ID representation.
  TraceId get traceIdValue => TraceId(_traceId);

  /// Typed span ID representation.
  SpanId get spanIdValue => SpanId(_spanId);

  /// Typed tracestate representation, if any.
  TraceState? get traceStateValue =>
      _traceState == null ? null : TraceState(_traceState);

  /// Whether both IDs are valid non-zero lowercase hexadecimal values.
  bool get isValid => traceIdValue.isValid && spanIdValue.isValid;
}
