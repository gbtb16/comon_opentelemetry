import 'dart:async';

import '../exporters/log_exporter.dart';
import 'log_processor.dart';
import 'log_record.dart';

/// Log processor that exports each record immediately.
final class SimpleLogProcessor implements LogProcessor {
  /// Creates a simple log processor.
  SimpleLogProcessor(this.exporter);

  /// Exporter used for each emitted log record.
  final LogExporter exporter;
  final Set<Future<void>> _pendingExports = <Future<void>>{};

  @override
  /// Exports [record] immediately.
  void onEmit(LogRecord record) {
    late final Future<void> pending;
    pending = exporter
        .export(<LogRecord>[record])
        .then<void>((_) {})
        .catchError((_) {})
        .whenComplete(() => _pendingExports.remove(pending));
    _pendingExports.add(pending);
    unawaited(pending);
  }

  @override
  /// Waits for in-flight exports and flushes the exporter.
  Future<void> forceFlush() async {
    while (_pendingExports.isNotEmpty) {
      await Future.wait(_pendingExports.toList());
    }
    await exporter.forceFlush();
  }

  @override
  /// Flushes outstanding exports and shuts down the exporter.
  Future<void> shutdown() async {
    await forceFlush();
    await exporter.shutdown();
  }
}
