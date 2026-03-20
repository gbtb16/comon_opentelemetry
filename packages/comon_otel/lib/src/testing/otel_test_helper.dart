import '../core/otel.dart';
import '../exporters/in_memory/in_memory_log_exporter.dart';
import '../exporters/in_memory/in_memory_metric_exporter.dart';
import '../exporters/in_memory/in_memory_span_exporter.dart';
import '../logs/log_processor.dart';
import '../logs/simple_log_processor.dart';
import '../metrics/metric_reader.dart';
import '../trace/simple_span_processor.dart';
import '../trace/span_processor.dart';

/// Test helper that wires the SDK to in-memory exporters.
final class OtelTestHelper {
  /// Creates a helper with preconfigured in-memory exporters.
  OtelTestHelper._({
    required this.spanExporter,
    required this.metricExporter,
    required this.logExporter,
  });

  /// In-memory span exporter used by the helper.
  final InMemorySpanExporter spanExporter;

  /// In-memory metric exporter used by the helper.
  final InMemoryMetricExporter metricExporter;

  /// In-memory log exporter used by the helper.
  final InMemoryLogExporter logExporter;

  /// Initializes the SDK for tests and returns the helper.
  static Future<OtelTestHelper> setup({String serviceName = 'test'}) async {
    final helper = OtelTestHelper._(
      spanExporter: InMemorySpanExporter(),
      metricExporter: InMemoryMetricExporter(),
      logExporter: InMemoryLogExporter(),
    );

    await Otel.init(
      serviceName: serviceName,
      spanProcessors: <SpanProcessor>[SimpleSpanProcessor(helper.spanExporter)],
      metricReaders: <MetricReader>[
        ExportingMetricReader(exporter: helper.metricExporter),
      ],
      logProcessors: <LogProcessor>[SimpleLogProcessor(helper.logExporter)],
    );

    return helper;
  }

  /// Clears all collected telemetry.
  void reset() {
    spanExporter.clear();
    metricExporter.clear();
    logExporter.clear();
  }

  /// Shuts down the SDK created for the test.
  Future<void> shutdown() => Otel.shutdown();
}
