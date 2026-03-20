import 'dart:async';

import '../exporters/span_exporter.dart';
import 'span.dart';
import 'span_data.dart';
import 'span_processor.dart';

final class SimpleSpanProcessor implements SpanProcessor {
  SimpleSpanProcessor(this.exporter);

  final SpanExporter exporter;
  final Set<Future<void>> _pendingExports = <Future<void>>{};

  @override
  void onStart(Span span) {}

  @override
  void onEnd(Span span) {
    if (!span.isRecording || !span.sampled) {
      return;
    }

    late final Future<void> pending;
    pending = exporter
        .export(<SpanData>[span.toSpanData()])
        .then<void>((_) {})
        .catchError((_) {})
        .whenComplete(() => _pendingExports.remove(pending));
    _pendingExports.add(pending);
    unawaited(pending);
  }

  @override
  Future<void> forceFlush() async {
    while (_pendingExports.isNotEmpty) {
      await Future.wait(_pendingExports.toList());
    }
    await exporter.forceFlush();
  }

  @override
  Future<void> shutdown() async {
    await forceFlush();
    await exporter.shutdown();
  }
}
