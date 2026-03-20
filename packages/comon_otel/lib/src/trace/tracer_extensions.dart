import 'dart:async';

import '../context/otel_context.dart';
import '../core/otel.dart';
import 'span_kind.dart';
import 'span_link.dart';
import 'span_status.dart';
import 'tracer.dart';

extension TracerHelpers on Tracer {
  R trace<R>(
    String name, {
    required R Function() fn,
    SpanKind kind = SpanKind.internal,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
    OtelContextSnapshot? parentSnapshot,
  }) {
    final span = startSpan(
      name,
      kind: kind,
      attributes: attributes,
      links: links,
      parentSnapshot: parentSnapshot,
    );
    return OtelContext.withSpan(span, () {
      try {
        final result = fn();
        span.setStatus(SpanStatus.ok);
        return result;
      } catch (error, stackTrace) {
        span.recordException(error, stackTrace: stackTrace);
        span.setStatus(SpanStatus.error, description: error.toString());
        rethrow;
      } finally {
        unawaited(span.end());
      }
    });
  }

  Future<R> traceAsync<R>(
    String name, {
    required Future<R> Function() fn,
    SpanKind kind = SpanKind.internal,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
    OtelContextSnapshot? parentSnapshot,
  }) async {
    final span = startSpan(
      name,
      kind: kind,
      attributes: attributes,
      links: links,
      parentSnapshot: parentSnapshot,
    );
    return OtelContext.withSpan(span, () async {
      try {
        final result = await fn();
        span.setStatus(SpanStatus.ok);
        return result;
      } catch (error, stackTrace) {
        span.recordException(error, stackTrace: stackTrace);
        span.setStatus(SpanStatus.error, description: error.toString());
        rethrow;
      } finally {
        await span.end();
      }
    });
  }
}

extension TracedFunction<R> on R Function() {
  R traced(
    String name, {
    Map<String, Object>? attributes,
    SpanKind kind = SpanKind.internal,
    Tracer? tracer,
    List<SpanLink>? links,
    OtelContextSnapshot? parentSnapshot,
  }) {
    return (tracer ?? Otel.instance.tracer).trace(
      name,
      kind: kind,
      attributes: attributes,
      links: links,
      parentSnapshot: parentSnapshot,
      fn: this,
    );
  }
}

extension TracedAsyncFunction<R> on Future<R> Function() {
  Future<R> traced(
    String name, {
    Map<String, Object>? attributes,
    SpanKind kind = SpanKind.internal,
    Tracer? tracer,
    List<SpanLink>? links,
    OtelContextSnapshot? parentSnapshot,
  }) {
    return (tracer ?? Otel.instance.tracer).traceAsync(
      name,
      kind: kind,
      attributes: attributes,
      links: links,
      parentSnapshot: parentSnapshot,
      fn: this,
    );
  }
}
