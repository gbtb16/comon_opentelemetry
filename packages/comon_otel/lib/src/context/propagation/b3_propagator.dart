import '../../trace/span_context.dart';
import '../../trace/trace_flags.dart';
import '../../trace/trace_id.dart';
import '../../trace/span_id.dart';
import '../baggage.dart';
import '../otel_context.dart';
import 'text_map_propagator.dart';

/// Propagates trace context using B3 single-header or multi-header formats.
final class B3Propagator implements TextMapPropagator {
  /// Creates a B3 propagator.
  const B3Propagator({this.useSingleHeader = false});

  /// Whether to emit the single `b3` header instead of the multi-header form.
  final bool useSingleHeader;

  @override
  void inject(OtelContextSnapshot context, Map<String, String> carrier) {
    final spanContext = context.spanContext;
    if (spanContext == null || !spanContext.isValid) {
      return;
    }

    final sampled = spanContext.sampled ? '1' : '0';
    if (useSingleHeader) {
      carrier['b3'] = '${spanContext.traceId}-${spanContext.spanId}-$sampled';
      return;
    }

    carrier['x-b3-traceid'] = spanContext.traceId;
    carrier['x-b3-spanid'] = spanContext.spanId;
    carrier['x-b3-sampled'] = sampled;
  }

  @override
  OtelContextSnapshot extract(Map<String, String> carrier) {
    if (carrier['b3'] case final singleHeader?) {
      final parts = singleHeader.split('-');
      if (parts.length >= 3 && parts[0].length == 32 && parts[1].length == 16) {
        return OtelContextSnapshot(
          spanContext: SpanContext.remote(
            traceId: TraceId(parts[0]),
            spanId: SpanId(parts[1]),
            traceFlags: TraceFlags.fromSampled(
              parts[2] == '1' || parts[2].toLowerCase() == 'd',
            ),
          ),
          baggage: Baggage.empty(),
        );
      }
    }

    final traceId = carrier['x-b3-traceid'];
    final spanId = carrier['x-b3-spanid'];
    final sampled = carrier['x-b3-sampled'];
    if (traceId == null || spanId == null) {
      return OtelContextSnapshot(baggage: Baggage.empty());
    }

    return OtelContextSnapshot(
      spanContext: SpanContext.remote(
        traceId: TraceId(traceId),
        spanId: SpanId(spanId),
        traceFlags: TraceFlags.fromSampled(
          sampled == '1' || sampled?.toLowerCase() == 'd',
        ),
      ),
      baggage: Baggage.empty(),
    );
  }
}
