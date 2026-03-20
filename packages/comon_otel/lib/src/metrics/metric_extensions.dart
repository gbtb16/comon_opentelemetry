import 'dart:async';

import 'instruments/histogram.dart';

extension TimedOperation on Histogram<double> {
  Future<R> time<R>(
    Future<R> Function() fn, {
    Map<String, Object>? attributes,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      stopwatch.stop();
      record(stopwatch.elapsedMilliseconds.toDouble(), attributes: attributes);
    }
  }
}
