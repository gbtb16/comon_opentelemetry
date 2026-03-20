import 'package:matcher/matcher.dart';

import '../context/baggage.dart';
import '../context/otel_context.dart';
import '../logs/log_record.dart';
import '../metrics/metric_data.dart';
import '../trace/span_context.dart';
import '../trace/span_data.dart';
import '../trace/span_status.dart';

/// Matcher for spans with a specific name.
Matcher hasSpanNamed(String name) {
  return predicate<SpanData>(
    (span) => span.name == name,
    'SpanData with name "$name"',
  );
}

/// Matcher for telemetry objects containing an attribute.
Matcher hasAttribute(String key, Object value) {
  return predicate<dynamic>((candidate) {
    if (candidate is SpanData) {
      return candidate.attributes[key] == value;
    }
    if (candidate is LogRecord) {
      return candidate.attributes[key] == value;
    }
    return false;
  }, 'candidate with attribute $key=$value');
}

/// Matcher for spans with a specific status.
Matcher hasStatus(SpanStatus status) {
  return predicate<SpanData>(
    (span) => span.status == status,
    'SpanData with status ${status.name}',
  );
}

/// Matcher for spans with a given parent span ID.
Matcher hasParentSpanId(String parentSpanId) {
  return predicate<SpanData>(
    (span) => span.parentSpanId == parentSpanId,
    'SpanData with parent span id $parentSpanId',
  );
}

/// Matcher for logs with a specific body.
Matcher hasLogBody(String body) {
  return predicate<LogRecord>(
    (log) => log.body == body,
    'LogRecord with body "$body"',
  );
}

/// Matcher for metrics with a specific name.
Matcher hasMetricNamed(String name) {
  return predicate<MetricData>(
    (metric) => metric.name == name,
    'MetricData with name "$name"',
  );
}

/// Matcher for metrics with a specific instrument type.
Matcher hasMetricType(MetricInstrumentType type) {
  return predicate<MetricData>(
    (metric) => metric.instrumentType == type,
    'MetricData with instrument type ${type.name}',
  );
}

/// Matcher for metrics containing a point with [value].
Matcher hasPointValue(num value) {
  return predicate<MetricData>(
    (metric) => metric.points.any((point) => point.value == value),
    'MetricData with a point value of $value',
  );
}

/// Matcher for metrics containing a point attribute.
Matcher hasPointAttribute(String key, Object value) {
  return predicate<MetricData>(
    (metric) => metric.points.any((point) => point.attributes[key] == value),
    'MetricData with a point attribute $key=$value',
  );
}

/// Matcher for telemetry objects associated with a trace ID.
Matcher hasTraceId(String traceId) {
  return predicate<dynamic>((candidate) {
    if (candidate is SpanData) {
      return candidate.traceId == traceId;
    }
    if (candidate is LogRecord) {
      return candidate.traceId == traceId;
    }
    if (candidate is SpanContext) {
      return candidate.traceId == traceId;
    }
    if (candidate is OtelContextSnapshot) {
      return candidate.traceId == traceId;
    }
    return false;
  }, 'candidate with trace id $traceId');
}

/// Matcher for string carriers containing a header.
Matcher hasCarrierHeader(String key, [String? value]) {
  return predicate<Map<String, String>>(
    (carrier) =>
        value == null ? carrier.containsKey(key) : carrier[key] == value,
    value == null
        ? 'carrier containing header $key'
        : 'carrier containing header $key=$value',
  );
}

/// Matcher for baggage entries.
Matcher hasBaggageEntry(String key, String value) {
  return predicate<dynamic>((candidate) {
    if (candidate is Baggage) {
      return candidate.getEntry(key) == value;
    }
    if (candidate is OtelContextSnapshot) {
      return candidate.baggage.getEntry(key) == value;
    }
    return false;
  }, 'candidate with baggage entry $key=$value');
}

/// Matcher for remote span contexts with optional field checks.
Matcher hasRemoteSpanContext({String? traceId, String? spanId, bool? sampled}) {
  return predicate<dynamic>((candidate) {
    final spanContext = switch (candidate) {
      SpanContext context => context,
      SpanData span => span.spanContext,
      LogRecord log => log.spanContext,
      OtelContextSnapshot snapshot => snapshot.spanContext,
      _ => null,
    };
    if (spanContext == null || !spanContext.isRemote) {
      return false;
    }
    if (traceId != null && spanContext.traceId != traceId) {
      return false;
    }
    if (spanId != null && spanContext.spanId != spanId) {
      return false;
    }
    if (sampled != null && spanContext.sampled != sampled) {
      return false;
    }
    return true;
  }, 'remote span context matcher');
}

/// Matcher for log severity.
Matcher hasSeverity(SeverityMatcher severity) {
  return predicate<LogRecord>(
    (log) => log.severity.name == severity.name,
    'LogRecord with severity ${severity.name}',
  );
}

/// Lightweight severity matcher wrapper for log assertions.
final class SeverityMatcher {
  /// Creates a severity matcher.
  const SeverityMatcher._(this.name);

  /// Expected severity name.
  final String name;

  static const SeverityMatcher trace = SeverityMatcher._('trace');
  static const SeverityMatcher debug = SeverityMatcher._('debug');
  static const SeverityMatcher info = SeverityMatcher._('info');
  static const SeverityMatcher warn = SeverityMatcher._('warn');
  static const SeverityMatcher error = SeverityMatcher._('error');
  static const SeverityMatcher fatal = SeverityMatcher._('fatal');
}
