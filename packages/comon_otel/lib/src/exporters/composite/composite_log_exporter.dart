import '../../logs/log_record.dart';
import '../log_exporter.dart';
import '../span_exporter.dart';

/// Log exporter that fans out exports to multiple exporters.
final class CompositeLogExporter implements LogExporter {
  /// Creates a composite log exporter.
  CompositeLogExporter(List<LogExporter> exporters)
    : _exporters = List<LogExporter>.unmodifiable(exporters);

  final List<LogExporter> _exporters;

  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    var hasFailure = false;

    for (final exporter in _exporters) {
      final result = await exporter.export(logs);
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
