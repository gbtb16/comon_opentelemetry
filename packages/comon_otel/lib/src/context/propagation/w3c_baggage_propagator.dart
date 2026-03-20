import '../baggage.dart';
import '../otel_context.dart';
import 'text_map_propagator.dart';

/// Propagates baggage using the W3C `baggage` header.
final class W3CBaggagePropagator implements TextMapPropagator {
  /// Creates a W3C baggage propagator.
  const W3CBaggagePropagator();

  @override
  void inject(OtelContextSnapshot context, Map<String, String> carrier) {
    if (context.baggage.entries.isEmpty) {
      return;
    }

    carrier['baggage'] = context.baggage.entries.entries
        .map((entry) {
          final metadata = entry.value.metadata;
          return metadata == null
              ? '${entry.key}=${entry.value.value}'
              : '${entry.key}=${entry.value.value};$metadata';
        })
        .join(',');
  }

  @override
  OtelContextSnapshot extract(Map<String, String> carrier) {
    final header = carrier['baggage'];
    if (header == null || header.trim().isEmpty) {
      return OtelContextSnapshot(baggage: Baggage.empty());
    }

    var baggage = Baggage.empty();
    for (final item in header.split(',')) {
      final parts = item.trim().split(';');
      final keyValue = parts.first.split('=');
      if (keyValue.length != 2) {
        continue;
      }
      baggage = baggage.withEntry(
        keyValue[0].trim(),
        keyValue[1].trim(),
        metadata: parts.length > 1 ? parts.sublist(1).join(';').trim() : null,
      );
    }

    return OtelContextSnapshot(baggage: baggage);
  }
}
