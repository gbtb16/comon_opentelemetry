import '../core/resource.dart';
import 'log_processor.dart';
import 'log_record.dart';
import 'otel_logger.dart';

/// Owns loggers and dispatches records through configured processors.
final class LoggerProvider {
  /// Creates a logger provider with [resource] and [logProcessors].
  LoggerProvider({
    required this.resource,
    required List<LogProcessor> logProcessors,
  }) : _logProcessors = List<LogProcessor>.unmodifiable(logProcessors);

  /// Resource attached to emitted log records.
  final Resource resource;
  final List<LogProcessor> _logProcessors;

  /// Returns a logger with the given [name].
  OtelLogger getLogger(String name) {
    return OtelLogger(provider: this, name: name);
  }

  /// Sends [record] through every configured log processor.
  void emit(LogRecord record) {
    for (final processor in _logProcessors) {
      processor.onEmit(record);
    }
  }

  /// Flushes all configured log processors.
  Future<void> forceFlush() async {
    for (final processor in _logProcessors) {
      await processor.forceFlush();
    }
  }

  /// Shuts down all configured log processors.
  Future<void> shutdown() async {
    for (final processor in _logProcessors) {
      await processor.shutdown();
    }
  }
}
