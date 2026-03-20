import '../../logs/log_record.dart';
import '../log_exporter.dart';
import '../span_exporter.dart';

/// Test-friendly log exporter that stores log records in memory.
final class InMemoryLogExporter implements LogExporter {
  /// Collected log records in export order.
  final List<LogRecord> logs = <LogRecord>[];

  /// Number of times [forceFlush] was called.
  int forceFlushCount = 0;

  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    this.logs.addAll(logs);
    return ExportResult.success;
  }

  /// Returns the most recent log emitted by [loggerName], if any.
  LogRecord? lastLogNamed(String loggerName) {
    for (var index = logs.length - 1; index >= 0; index -= 1) {
      final log = logs[index];
      if (log.loggerName == loggerName) {
        return log;
      }
    }
    return null;
  }

  /// Removes all collected log records.
  void clear() => logs.clear();

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}
