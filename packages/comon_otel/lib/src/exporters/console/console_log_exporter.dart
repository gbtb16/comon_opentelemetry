import 'dart:convert';

import '../../logs/log_record.dart';
import '../log_exporter.dart';
import '../span_exporter.dart';

/// Log exporter that prints log records as JSON to stdout.
final class ConsoleLogExporter implements LogExporter {
  /// Creates a console log exporter.
  ConsoleLogExporter({this.pretty = true});

  /// Whether to pretty-print JSON output.
  final bool pretty;

  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();

    for (final log in logs) {
      print(
        encoder.convert(<String, Object?>{
          'timestamp': log.timestamp.toIso8601String(),
          'observedTimestamp': log.observedTimestamp?.toIso8601String(),
          'severity': log.severity.name,
          'severityValue': log.severity.value,
          'severityText': log.severityText,
          'body': log.body,
          'loggerName': log.loggerName,
          'spanContext': log.traceId == null
              ? null
              : <String, Object?>{
                  'traceId': log.traceId,
                  'spanId': log.spanId,
                  'sampled': log.sampled,
                },
          'attributes': log.attributes,
          'resource': log.resource.attributes,
        }),
      );
    }

    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
