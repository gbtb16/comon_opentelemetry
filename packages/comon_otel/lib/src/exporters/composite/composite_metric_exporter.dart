import '../../metrics/metric_data.dart';
import '../metric_exporter.dart';
import '../span_exporter.dart';

/// Metric exporter that fans out exports to multiple exporters.
final class CompositeMetricExporter implements MetricExporter {
  /// Creates a composite metric exporter.
  CompositeMetricExporter(List<MetricExporter> exporters)
    : _exporters = List<MetricExporter>.unmodifiable(exporters);

  final List<MetricExporter> _exporters;

  @override
  Future<ExportResult> export(List<MetricData> metrics) async {
    var hasFailure = false;

    for (final exporter in _exporters) {
      final result = await exporter.export(metrics);
      if (result == ExportResult.failure) {
        hasFailure = true;
      }
    }

    return hasFailure ? ExportResult.failure : ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {
    for (final exporter in _exporters) {
      await exporter.forceFlush();
    }
  }

  @override
  Future<void> shutdown() async {
    for (final exporter in _exporters) {
      await exporter.shutdown();
    }
  }
}
