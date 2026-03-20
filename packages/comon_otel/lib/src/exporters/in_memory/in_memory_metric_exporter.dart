import '../../metrics/metric_data.dart';
import '../metric_exporter.dart';
import '../span_exporter.dart';

/// Test-friendly metric exporter that stores metrics in memory.
final class InMemoryMetricExporter implements MetricExporter {
  /// Collected metrics in export order.
  final List<MetricData> metrics = <MetricData>[];

  /// Number of times [forceFlush] was called.
  int forceFlushCount = 0;

  @override
  Future<ExportResult> export(List<MetricData> metrics) async {
    this.metrics.addAll(metrics);
    return ExportResult.success;
  }

  /// Returns the most recent metric with the given [name], if any.
  MetricData? lastMetricNamed(String name) {
    for (var index = metrics.length - 1; index >= 0; index -= 1) {
      final metric = metrics[index];
      if (metric.name == name) {
        return metric;
      }
    }
    return null;
  }

  /// Removes all collected metrics.
  void clear() => metrics.clear();

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}
