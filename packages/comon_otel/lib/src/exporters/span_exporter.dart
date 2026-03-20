import '../trace/span_data.dart';

/// Result returned by an exporter operation.
enum ExportResult {
  /// Export completed successfully.
  success,

  /// Export failed.
  failure,
}

/// Exports completed spans to an external sink.
abstract interface class SpanExporter {
  /// Exports [spans].
  Future<ExportResult> export(List<SpanData> spans);

  /// Flushes any buffered data.
  Future<void> forceFlush();

  /// Releases resources and stops exporting.
  Future<void> shutdown();
}
