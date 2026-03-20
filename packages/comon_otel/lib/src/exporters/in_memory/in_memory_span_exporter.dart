import '../../trace/span_data.dart';
import '../span_exporter.dart';

/// Test-friendly span exporter that stores spans in memory.
final class InMemorySpanExporter implements SpanExporter {
  /// Collected spans in export order.
  final List<SpanData> spans = <SpanData>[];

  /// Number of times [forceFlush] was called.
  int forceFlushCount = 0;

  @override
  Future<ExportResult> export(List<SpanData> spans) async {
    this.spans.addAll(spans);
    return ExportResult.success;
  }

  /// Returns the most recent span with the given [name], if any.
  SpanData? lastSpanNamed(String name) {
    for (var index = spans.length - 1; index >= 0; index -= 1) {
      final span = spans[index];
      if (span.name == name) {
        return span;
      }
    }
    return null;
  }

  /// Returns every collected span with the given [name].
  List<SpanData> spansNamed(String name) {
    return spans.where((span) => span.name == name).toList(growable: false);
  }

  /// Removes all collected spans.
  void clear() => spans.clear();

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}
