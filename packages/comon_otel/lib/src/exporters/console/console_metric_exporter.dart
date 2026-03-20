import 'dart:convert';

import '../../metrics/metric_data.dart';
import '../metric_exporter.dart';
import '../span_exporter.dart';

/// Metric exporter that prints metrics as JSON to stdout.
final class ConsoleMetricExporter implements MetricExporter {
  /// Creates a console metric exporter.
  ConsoleMetricExporter({this.pretty = true});

  /// Whether to pretty-print JSON output.
  final bool pretty;

  @override
  Future<ExportResult> export(List<MetricData> metrics) async {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();

    for (final metric in metrics) {
      print(
        encoder.convert(<String, Object?>{
          'name': metric.name,
          'description': metric.description,
          'unit': metric.unit,
          'instrumentType': metric.instrumentType.name,
          'instrumentationScope': metric.instrumentationScope,
          'resource': metric.resource.attributes,
          'points': metric.points
              .map(
                (point) => <String, Object?>{
                  'value': point.value,
                  'attributes': point.attributes,
                  'timestamp': point.timestamp.toIso8601String(),
                },
              )
              .toList(growable: false),
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
