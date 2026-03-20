import 'log_record.dart';

/// Receives log records and forwards them to exporters.
abstract interface class LogProcessor {
  /// Handles a newly emitted [record].
  void onEmit(LogRecord record);

  /// Flushes buffered records, if any.
  Future<void> forceFlush();

  /// Releases resources and stops exporting logs.
  Future<void> shutdown();
}
