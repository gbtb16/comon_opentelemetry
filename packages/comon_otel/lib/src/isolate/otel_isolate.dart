import 'dart:async';
import 'dart:isolate';

import '../context/baggage.dart';
import '../context/otel_context.dart';
import '../core/otel.dart';
import '../core/semantic_attributes.dart';
import '../trace/trace_flags.dart';
import '../trace/span_context.dart';
import '../trace/trace_id.dart';
import '../trace/span_id.dart';
import '../trace/trace_state.dart';

/// Callback executed inside [OtelIsolate.run].
typedef OtelIsolateCallback<R> =
    FutureOr<R> Function(OtelIsolateContext context);

/// Optional initializer executed inside the spawned isolate before work starts.
typedef OtelIsolateInitializer = FutureOr<void> Function();

/// Serializable trace and baggage context passed into an isolate.
final class OtelIsolateContext {
  /// Creates an isolate context.
  const OtelIsolateContext({
    this.spanContext,
    this.baggage = const <String, BaggageEntry>{},
  });

  /// Captures the current context from the active isolate.
  factory OtelIsolateContext.capture() {
    final snapshot = OtelContext.current;
    return OtelIsolateContext(
      spanContext: snapshot.spanContext,
      baggage: snapshot.baggage.entries,
    );
  }

  /// Reconstructs an isolate context from a message payload.
  factory OtelIsolateContext.fromMessage(Map<String, Object?> message) {
    final baggageEntries =
        (message['baggage'] as Map<Object?, Object?>?) ??
        const <Object?, Object?>{};

    return OtelIsolateContext(
      spanContext: switch (message['spanContext']) {
        final Map<Object?, Object?> raw =>
          (raw['isRemote']! as bool)
              ? SpanContext.remote(
                  traceId: TraceId(raw['traceId']! as String),
                  spanId: SpanId(raw['spanId']! as String),
                  traceFlags: TraceFlags(raw['traceFlags']! as int),
                  traceState: switch (raw['traceState']) {
                    final String traceState => TraceState(traceState),
                    _ => null,
                  },
                )
              : SpanContext.local(
                  traceId: TraceId(raw['traceId']! as String),
                  spanId: SpanId(raw['spanId']! as String),
                  traceFlags: TraceFlags(raw['traceFlags']! as int),
                  traceState: switch (raw['traceState']) {
                    final String traceState => TraceState(traceState),
                    _ => null,
                  },
                ),
        _ => null,
      },
      baggage: baggageEntries.map(
        (key, value) => MapEntry(
          key! as String,
          BaggageEntry(
            value: (value as Map<Object?, Object?>)['value']! as String,
            metadata: value['metadata'] as String?,
          ),
        ),
      ),
    );
  }

  /// Span context propagated into the isolate, if any.
  final SpanContext? spanContext;

  /// Baggage entries propagated into the isolate.
  final Map<String, BaggageEntry> baggage;

  /// Baggage as a [Baggage] value object.
  Baggage get baggageValue => Baggage.fromEntries(baggage);

  /// Trace ID associated with [spanContext], if any.
  String? get traceId => spanContext?.traceId;

  /// Span ID associated with [spanContext], if any.
  String? get spanId => spanContext?.spanId;

  /// Whether the propagated span context is sampled.
  bool? get sampled => spanContext?.sampled;

  /// Serialized tracestate associated with [spanContext], if any.
  String? get traceState => spanContext?.traceState;

  /// Typed trace ID associated with [spanContext], if any.
  TraceId? get traceIdValue => spanContext?.traceIdValue;

  /// Typed span ID associated with [spanContext], if any.
  SpanId? get spanIdValue => spanContext?.spanIdValue;

  /// Trace flags associated with [spanContext], if any.
  TraceFlags? get traceFlags => spanContext?.traceFlags;

  /// Typed tracestate associated with [spanContext], if any.
  TraceState? get traceStateValue => spanContext?.traceStateValue;

  /// Serializes the context into a message-safe structure.
  Map<String, Object?> toMessage() {
    return <String, Object?>{
      'spanContext': spanContext == null
          ? null
          : <String, Object?>{
              'traceId': traceId,
              'spanId': spanId,
              'traceFlags': traceFlags!.value,
              'isRemote': spanContext!.isRemote,
              'traceState': traceState,
            },
      'baggage': baggage.map(
        (key, value) => MapEntry(key, <String, Object?>{
          'value': value.value,
          'metadata': value.metadata,
        }),
      ),
    };
  }
}

/// Helpers for carrying OpenTelemetry context across isolate boundaries.
final class OtelIsolate {
  const OtelIsolate._();

  /// Captures the current isolate context.
  static OtelIsolateContext captureCurrent() => OtelIsolateContext.capture();

  /// Runs [callback] in a new isolate with propagated trace context and baggage.
  static Future<R> run<R>(
    OtelIsolateCallback<R> callback, {
    String? spanName,
    OtelIsolateInitializer? initialize,
  }) async {
    final message = captureCurrent().toMessage();

    return Isolate.run(() async {
      final context = OtelIsolateContext.fromMessage(message);
      Baggage.registerCurrentResolver(() => OtelContext.currentBaggage);

      final wasInitialized = Otel.isInitialized;
      if (initialize != null) {
        await initialize();
      }
      final initializedHere = !wasInitialized && Otel.isInitialized;

      final baggage = context.baggageValue;
      try {
        if (spanName != null &&
            context.spanContext != null &&
            Otel.isInitialized) {
          final span = Otel.instance.tracer.startSpan(
            spanName,
            parentSnapshot: OtelContextSnapshot(
              spanContext: context.spanContext,
              baggage: baggage,
            ),
            parentContext: context.spanContext,
            attributes: <String, Object>{
              SemanticAttributes.threadType: 'isolate',
            },
          );
          return await OtelContext.withValues(
            span: span,
            baggage: baggage,
            fn: () async {
              try {
                return await callback(context);
              } finally {
                await span.end();
              }
            },
          );
        }

        return await OtelContext.withBaggage(
          baggage,
          () async => await callback(context),
        );
      } finally {
        if (initializedHere) {
          await Otel.shutdown();
        }
      }
    });
  }
}
