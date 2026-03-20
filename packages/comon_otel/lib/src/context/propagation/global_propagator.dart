import 'b3_propagator.dart';
import 'composite_propagator.dart';
import 'text_map_propagator.dart';
import 'w3c_baggage_propagator.dart';
import 'w3c_trace_context_propagator.dart';

/// Global registry for the active text map propagator.
final class GlobalPropagators {
  const GlobalPropagators._();

  /// Default propagator combining W3C trace context and baggage.
  static const TextMapPropagator defaultPropagator = CompositePropagator(
    <TextMapPropagator>[W3CTraceContextPropagator(), W3CBaggagePropagator()],
  );

  static TextMapPropagator _instance = defaultPropagator;

  /// Currently configured global propagator.
  static TextMapPropagator get instance => _instance;

  /// Replaces the current global propagator.
  static void set(TextMapPropagator propagator) {
    _instance = propagator;
  }

  /// Restores [defaultPropagator].
  static void reset() {
    _instance = defaultPropagator;
  }

  /// Parses a comma-separated propagator list into a concrete propagator.
  static TextMapPropagator? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final tokens = raw
        .split(',')
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return null;
    }

    if (tokens.contains('none')) {
      return tokens.length == 1
          ? const CompositePropagator(<TextMapPropagator>[])
          : null;
    }

    final propagators = <TextMapPropagator>[];
    for (final token in tokens) {
      switch (token) {
        case 'tracecontext':
          propagators.add(const W3CTraceContextPropagator());
        case 'baggage':
          propagators.add(const W3CBaggagePropagator());
        case 'b3':
          propagators.add(const B3Propagator(useSingleHeader: true));
        case 'b3multi':
          propagators.add(const B3Propagator());
        default:
          return null;
      }
    }

    if (propagators.length == 1) {
      return propagators.single;
    }

    return CompositePropagator(propagators);
  }
}
