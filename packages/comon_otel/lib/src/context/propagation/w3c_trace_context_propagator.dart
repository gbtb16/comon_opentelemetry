import '../../trace/span_context.dart';
import '../../trace/trace_flags.dart';
import '../../trace/trace_id.dart';
import '../../trace/span_id.dart';
import '../../trace/trace_state.dart';
import '../baggage.dart';
import '../otel_context.dart';
import 'text_map_propagator.dart';

/// Propagates trace context using the W3C `traceparent` and `tracestate` headers.
final class W3CTraceContextPropagator implements TextMapPropagator {
  /// Creates a W3C trace context propagator.
  const W3CTraceContextPropagator();

  @override
  void inject(OtelContextSnapshot context, Map<String, String> carrier) {
    final spanContext = context.spanContext;
    if (spanContext == null || !spanContext.isValid) {
      return;
    }

    carrier['traceparent'] =
        '00-${spanContext.traceId}-${spanContext.spanId}-${spanContext.traceFlags.hex}';

    final traceState = spanContext.traceStateValue?.normalized;
    if (traceState != null) {
      carrier['tracestate'] = traceState;
    }
  }

  @override
  OtelContextSnapshot extract(Map<String, String> carrier) {
    final header = carrier['traceparent'];
    if (header == null) {
      return OtelContextSnapshot(baggage: Baggage.empty());
    }

    final parts = header.trim().split('-');
    if (parts.length != 4) {
      return OtelContextSnapshot(baggage: Baggage.empty());
    }

    final version = parts[0].toLowerCase();
    final traceId = TraceId(parts[1]);
    final spanId = SpanId(parts[2]);
    final flags = parts[3].toLowerCase();
    final traceFlags = TraceFlags.tryParseHex(flags);

    if (!_isValidVersion(version) || !traceId.isValid) {
      return OtelContextSnapshot(baggage: Baggage.empty());
    }

    if (!spanId.isValid ||
        traceFlags == null ||
        !_isValidFlags(version, flags)) {
      return OtelContextSnapshot(baggage: Baggage.empty());
    }

    return OtelContextSnapshot(
      spanContext: SpanContext.remote(
        traceId: traceId,
        spanId: spanId,
        traceFlags: traceFlags,
        traceState: TraceState.tryParse(carrier['tracestate']),
      ),
      baggage: Baggage.empty(),
    );
  }

  bool _isValidVersion(String version) {
    return version.length == 2 && _isHex(version) && version != 'ff';
  }

  bool _isValidFlags(String version, String flags) {
    if (flags.length != 2 || !_isHex(flags)) {
      return false;
    }

    if (version == '00') {
      final numeric = int.parse(flags, radix: 16);
      return (numeric & 0xfc) == 0;
    }

    return true;
  }

  bool _isHex(String value) {
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final isLowerHex = codeUnit >= 0x61 && codeUnit <= 0x66;
      if (!isDigit && !isLowerHex) {
        return false;
      }
    }
    return value.isNotEmpty;
  }
}
