import '../../trace/span_data.dart';
import '../span_exporter.dart';

/// Span exporter that fans out exports to multiple exporters.
final class CompositeSpanExporter implements SpanExporter {
  /// Creates a composite span exporter.
  CompositeSpanExporter(List<SpanExporter> exporters)
    : _exporters = List<SpanExporter>.unmodifiable(exporters);

  final List<SpanExporter> _exporters;

  @override
  Future<ExportResult> export(List<SpanData> spans) async {
    var hasFailure = false;

    for (final exporter in _exporters) {
      final result = await exporter.export(spans);
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
