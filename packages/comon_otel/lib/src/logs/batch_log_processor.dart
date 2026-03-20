import 'dart:async';
import 'dart:collection';

import '../exporters/log_exporter.dart';
import 'log_processor.dart';
import 'log_record.dart';

/// Log processor that buffers records and exports them in batches.
final class BatchLogProcessor implements LogProcessor {
  /// Creates a batch log processor.
  BatchLogProcessor({
    required LogExporter exporter,
    this.maxBatchSize = 512,
    this.scheduleDelay = const Duration(seconds: 1),
    this.maxQueueSize = 2048,
    this.exportTimeout,
  }) : _exporter = exporter {
    _timer = Timer.periodic(scheduleDelay, (_) {
      unawaited(_flushBatch());
    });
  }

  final LogExporter _exporter;

  /// Maximum number of records exported in one batch.
  final int maxBatchSize;

  /// Delay between scheduled batch exports.
  final Duration scheduleDelay;

  /// Maximum number of queued records retained before dropping oldest items.
  final int maxQueueSize;

  /// Optional timeout applied to each export operation.
  final Duration? exportTimeout;
  final Queue<LogRecord> _queue = Queue<LogRecord>();

  Timer? _timer;
  bool _isShutdown = false;
  Future<void> _pendingFlush = Future<void>.value();

  @override
  /// Queues [record] for batched export.
  void onEmit(LogRecord record) {
    if (_isShutdown) {
      return;
    }

    if (_queue.length >= maxQueueSize) {
      _queue.removeFirst();
    }
    _queue.addLast(record);

    if (_queue.length >= maxBatchSize) {
      unawaited(_flushBatch());
    }
  }

  @override
  /// Flushes queued records and then flushes the exporter.
  Future<void> forceFlush() async {
    await _flushBatch(all: true);
    await _exporter.forceFlush();
  }

  @override
  /// Stops the processor, flushes queued records, and shuts down the exporter.
  Future<void> shutdown() async {
    if (_isShutdown) {
      return;
    }
    _isShutdown = true;
    _timer?.cancel();
    await _flushBatch(all: true);
    await _exporter.shutdown();
  }

  Future<void> _flushBatch({bool all = false}) {
    _pendingFlush = _pendingFlush.then((_) async {
      if (_queue.isEmpty) {
        return;
      }

      do {
        final batch = <LogRecord>[];
        final limit = all ? _queue.length : maxBatchSize;
        while (_queue.isNotEmpty && batch.length < limit) {
          batch.add(_queue.removeFirst());
        }

        if (batch.isNotEmpty) {
          final exportFuture = _exporter.export(batch);
          if (exportTimeout == null) {
            await exportFuture;
          } else {
            await exportFuture.timeout(exportTimeout!);
          }
        }
      } while (all && _queue.isNotEmpty);
    });

    return _pendingFlush;
  }
}
