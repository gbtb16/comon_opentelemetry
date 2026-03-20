import '../baggage.dart';
import '../otel_context.dart';
import '../../trace/span_context.dart';
import 'text_map_propagator.dart';

/// Propagator that applies multiple propagators in sequence.
final class CompositePropagator implements TextMapPropagator {
  /// Creates a composite propagator.
  const CompositePropagator(this.propagators);

  /// Ordered propagators used for injection and extraction.
  final List<TextMapPropagator> propagators;

  @override
  void inject(OtelContextSnapshot context, Map<String, String> carrier) {
    for (final propagator in propagators) {
      propagator.inject(context, carrier);
    }
  }

  @override
  OtelContextSnapshot extract(Map<String, String> carrier) {
    SpanContext? spanContext;
    var baggage = Baggage.empty();

    for (final propagator in propagators) {
      final extracted = propagator.extract(carrier);
      spanContext ??= extracted.spanContext;
      baggage = baggage.merge(extracted.baggage);
    }

    return OtelContextSnapshot(spanContext: spanContext, baggage: baggage);
  }
}
