import '../exporters/metric_exporter.dart';
import 'meter_provider.dart';

abstract interface class MetricReader {
  void attach(MeterProvider provider);

  Future<void> collect();

  Future<void> forceFlush();

  Future<void> shutdown();
}

final class ExportingMetricReader implements MetricReader {
  ExportingMetricReader({required this.exporter});

  final MetricExporter exporter;
  MeterProvider? _provider;

  @override
  void attach(MeterProvider provider) {
    _provider = provider;
  }

  @override
  Future<void> collect() async {
    final provider = _provider;
    if (provider == null) {
      throw StateError('MetricReader is not attached to a MeterProvider.');
    }

    final metrics = provider.collectAll();
    if (metrics.isEmpty) {
      return;
    }

    await exporter.export(metrics);
  }

  @override
  Future<void> forceFlush() async {
    await collect();
    await exporter.forceFlush();
  }

  @override
  Future<void> shutdown() => exporter.shutdown();
}
