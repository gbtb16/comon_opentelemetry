import '../metrics/metric_data.dart';
import 'span_exporter.dart';

/// Exports collected metrics to an external sink.
abstract interface class MetricExporter {
  /// Exports [metrics].
  Future<ExportResult> export(List<MetricData> metrics);

  /// Flushes any buffered data.
  Future<void> forceFlush();

  /// Releases resources and stops exporting.
  Future<void> shutdown();
}
