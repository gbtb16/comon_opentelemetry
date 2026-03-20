import 'dart:convert';

import '../../trace/span_data.dart';
import '../span_exporter.dart';

/// Span exporter that prints spans as JSON to stdout.
final class ConsoleSpanExporter implements SpanExporter {
  /// Creates a console span exporter.
  ConsoleSpanExporter({this.pretty = true, this.includeTimestamps = true});

  /// Whether to pretty-print JSON output.
  final bool pretty;

  /// Whether to include timestamps in the printed payload.
  final bool includeTimestamps;

  @override
  Future<ExportResult> export(List<SpanData> spans) async {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();

    for (final span in spans) {
      final payload = <String, Object?>{
        'name': span.name,
        'traceId': span.traceId,
        'spanId': span.spanId,
        'parentSpanId': span.parentSpanId,
        'kind': span.kind.name,
        'status': span.status.name,
        'statusDescription': span.statusDescription,
        'attributes': span.attributes,
        'events': span.events
            .map(
              (event) => <String, Object?>{
                'name': event.name,
                'timestamp': includeTimestamps
                    ? event.timestamp.toIso8601String()
                    : null,
                'attributes': event.attributes,
              },
            )
            .toList(growable: false),
      };

      if (includeTimestamps) {
        payload['startTime'] = span.startTime.toIso8601String();
        payload['endTime'] = span.endTime.toIso8601String();
      }

      print(encoder.convert(payload));
    }

    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
