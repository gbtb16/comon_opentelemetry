import 'dart:async';

import 'baggage.dart';
import '../trace/span.dart';
import '../trace/span_id.dart';
import '../trace/span_context.dart';
import '../trace/trace_flags.dart';
import '../trace/trace_id.dart';
import '../trace/trace_state.dart';

final bool _baggageResolverRegistered = (() {
  Baggage.registerCurrentResolver(() => OtelContext.currentBaggage);
  return true;
})();

/// Immutable snapshot of the active span context and baggage.
final class OtelContextSnapshot {
  /// Creates a context snapshot.
  const OtelContextSnapshot({this.spanContext, required this.baggage});

  /// Creates a local context snapshot from typed identifiers.
  factory OtelContextSnapshot.local({
    required TraceId traceId,
    required SpanId spanId,
    TraceFlags traceFlags = TraceFlags.none,
    TraceState? traceState,
    Baggage? baggage,
  }) {
    return OtelContextSnapshot(
      spanContext: SpanContext.local(
        traceId: traceId,
        spanId: spanId,
        traceFlags: traceFlags,
        traceState: traceState,
      ),
      baggage: baggage ?? Baggage.empty(),
    );
  }

  /// Creates a remote context snapshot from extracted propagation data.
  factory OtelContextSnapshot.remote({
    required TraceId traceId,
    required SpanId spanId,
    TraceFlags traceFlags = TraceFlags.none,
    TraceState? traceState,
    Baggage? baggage,
  }) {
    return OtelContextSnapshot(
      spanContext: SpanContext.remote(
        traceId: traceId,
        spanId: spanId,
        traceFlags: traceFlags,
        traceState: traceState,
      ),
      baggage: baggage ?? Baggage.empty(),
    );
  }

  /// Span context carried by this snapshot, if any.
  final SpanContext? spanContext;

  /// Baggage carried by this snapshot.
  final Baggage baggage;

  /// Trace ID associated with [spanContext], if any.
  String? get traceId => spanContext?.traceId;

  /// Span ID associated with [spanContext], if any.
  String? get spanId => spanContext?.spanId;

  /// Whether the snapshot's span context is sampled, if any.
  bool? get sampled => spanContext?.sampled;

  /// Serialized tracestate from [spanContext], if any.
  String? get traceState => spanContext?.traceState;

  /// Whether the snapshot originated from a remote parent.
  bool get isRemote => spanContext?.isRemote ?? false;

  /// Typed trace ID associated with [spanContext], if any.
  TraceId? get traceIdValue => spanContext?.traceIdValue;

  /// Typed span ID associated with [spanContext], if any.
  SpanId? get spanIdValue => spanContext?.spanIdValue;

  /// Trace flags associated with [spanContext], if any.
  TraceFlags? get traceFlags => spanContext?.traceFlags;

  /// Typed tracestate associated with [spanContext], if any.
  TraceState? get traceStateValue => spanContext?.traceStateValue;
}

/// Zone-backed access to the current span and baggage.
final class OtelContext {
  static const Symbol _spanKey = #comonOtelCurrentSpan;
  static const Symbol _baggageKey = #comonOtelCurrentBaggage;

  const OtelContext._();

  /// Currently active span, if any.
  static Span? get currentSpan => Zone.current[_spanKey] as Span?;

  /// Currently active baggage.
  static Baggage get currentBaggage =>
      (_baggageResolverRegistered
          ? (Zone.current[_baggageKey] as Baggage?)
          : null) ??
      Baggage.empty();

  /// Current span context and baggage snapshot.
  static OtelContextSnapshot get current => OtelContextSnapshot(
    spanContext: currentSpan?.spanContext,
    baggage: currentBaggage,
  );

  /// Runs [fn] with [span] as the active span.
  static T withSpan<T>(Span span, T Function() fn) {
    return runZoned(
      fn,
      zoneValues: <Object?, Object?>{
        _spanKey: span,
        _baggageKey: currentBaggage,
      },
    );
  }

  /// Runs [fn] with [baggage] as the active baggage.
  static T withBaggage<T>(Baggage baggage, T Function() fn) {
    return runZoned(
      fn,
      zoneValues: <Object?, Object?>{
        _spanKey: currentSpan,
        _baggageKey: baggage,
      },
    );
  }

  /// Runs [fn] with explicit span and baggage overrides.
  static T withValues<T>({
    Span? span,
    Baggage? baggage,
    required T Function() fn,
  }) {
    return runZoned(
      fn,
      zoneValues: <Object?, Object?>{
        _spanKey: span ?? currentSpan,
        _baggageKey: baggage ?? currentBaggage,
      },
    );
  }
}
