import 'span.dart';

abstract interface class SpanProcessor {
  void onStart(Span span);

  void onEnd(Span span);

  Future<void> forceFlush();

  Future<void> shutdown();
}
