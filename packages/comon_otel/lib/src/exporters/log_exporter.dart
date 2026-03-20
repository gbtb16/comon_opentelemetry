import '../logs/log_record.dart';
import 'span_exporter.dart';

/// Exports log records to an external sink.
abstract interface class LogExporter {
  /// Exports [logs].
  Future<ExportResult> export(List<LogRecord> logs);

  /// Flushes any buffered data.
  Future<void> forceFlush();

  /// Releases resources and stops exporting.
  Future<void> shutdown();
}
