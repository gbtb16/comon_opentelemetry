import 'dart:convert';
import 'dart:typed_data';

import '../../../core/resource.dart';
import '../../../core/instrumentation_scope.dart';
import '../../../logs/log_record.dart';
import '../../../metrics/metric_data.dart';
import '../../../trace/span_data.dart';
import '../../../trace/span_link.dart';

final class OtlpProtobufCodec {
  const OtlpProtobufCodec._();

  static List<int> encodeSpans(List<SpanData> spans) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(
        1,
        _groupByResource(spans, _encodeResourceSpans),
      ),
    ]);
  }

  static List<int> encodeMetrics(List<MetricData> metrics) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(
        1,
        _groupByResource(metrics, _encodeResourceMetrics),
      ),
    ]);
  }

  static List<int> encodeLogs(List<LogRecord> logs) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(
        1,
        _groupByResource(logs, _encodeResourceLogs),
      ),
    ]);
  }

  static List<List<int>> _groupByResource<T>(
    List<T> items,
    List<int> Function(Resource resource, List<T> batch) builder,
  ) {
    final grouped = <String, List<T>>{};
    final resources = <String, Resource>{};

    for (final item in items) {
      final resource = switch (item) {
        SpanData span => span.resource,
        MetricData metric => metric.resource,
        LogRecord log => log.resource,
        _ => throw ArgumentError(
          'Unsupported OTLP item type: ${item.runtimeType}',
        ),
      };
      final key = '${resource.schemaUrl}|${resource.attributes}';
      resources[key] = resource;
      grouped.putIfAbsent(key, () => <T>[]).add(item);
    }

    return grouped.entries
        .map((entry) => builder(resources[entry.key]!, entry.value))
        .toList(growable: false);
  }

  static List<List<int>> _groupByScope<T>(
    List<T> items,
    List<int> Function(InstrumentationScope scope, List<T> batch) builder,
  ) {
    final grouped = <InstrumentationScope, List<T>>{};

    for (final item in items) {
      final scope = switch (item) {
        SpanData span =>
          span.scope ?? const InstrumentationScope(name: 'default'),
        MetricData metric =>
          metric.scope ?? const InstrumentationScope(name: 'default'),
        LogRecord log => InstrumentationScope(
          name: log.loggerName ?? 'default',
        ),
        _ => const InstrumentationScope(name: 'default'),
      };
      grouped.putIfAbsent(scope, () => <T>[]).add(item);
    }

    return grouped.entries
        .map((entry) => builder(entry.key, entry.value))
        .toList(growable: false);
  }

  static List<int> _encodeResourceSpans(
    Resource resource,
    List<SpanData> spans,
  ) {
    return _encodeMessage(<List<int>>[
      _encodeMessageField(1, _encodeResource(resource)),
      _encodeRepeatedMessageField(2, _groupByScope(spans, _encodeScopeSpans)),
      if (resource.schemaUrl != null)
        _encodeStringField(3, resource.schemaUrl!),
    ]);
  }

  static List<int> _encodeScopeSpans(
    InstrumentationScope scope,
    List<SpanData> spans,
  ) {
    return _encodeMessage(<List<int>>[
      _encodeMessageField(1, _encodeScope(scope)),
      _encodeRepeatedMessageField(
        2,
        spans.map(_encodeSpan).toList(growable: false),
      ),
      if (scope.schemaUrl != null) _encodeStringField(3, scope.schemaUrl!),
    ]);
  }

  static List<int> _encodeSpan(SpanData span) {
    return _encodeMessage(<List<int>>[
      _encodeBytesField(1, _decodeHex(span.traceIdValue.hex)),
      _encodeBytesField(2, _decodeHex(span.spanIdValue.hex)),
      if (span.traceState case final traceState?)
        _encodeStringField(3, traceState),
      if (span.parentSpanIdValue case final parent?)
        _encodeBytesField(4, _decodeHex(parent.hex)),
      _encodeStringField(5, span.name),
      _encodeEnumField(6, _encodeSpanKind(span.kind.name)),
      _encodeFixed64Field(7, _toUnixNanos(span.startTime)),
      _encodeFixed64Field(8, _toUnixNanos(span.endTime)),
      _encodeRepeatedMessageField(9, _encodeAttributes(span.attributes)),
      _encodeRepeatedMessageField(
        11,
        span.events.map(_encodeSpanEvent).toList(growable: false),
      ),
      _encodeRepeatedMessageField(
        13,
        span.links.map(_encodeSpanLink).toList(growable: false),
      ),
      _encodeMessageField(
        15,
        _encodeStatus(span.status.name, span.statusDescription),
      ),
    ]);
  }

  static List<int> _encodeSpanEvent(dynamic event) {
    return _encodeMessage(<List<int>>[
      _encodeFixed64Field(1, _toUnixNanos(event.timestamp as DateTime)),
      _encodeStringField(2, event.name as String),
      _encodeRepeatedMessageField(
        3,
        _encodeAttributes(event.attributes as Map<String, Object>),
      ),
    ]);
  }

  static List<int> _encodeStatus(String status, String? description) {
    return _encodeMessage(<List<int>>[
      if (description != null && description.isNotEmpty)
        _encodeStringField(2, description),
      _encodeEnumField(3, _encodeStatusCode(status)),
    ]);
  }

  static List<int> _encodeSpanLink(SpanLink link) {
    return _encodeMessage(<List<int>>[
      _encodeBytesField(1, _decodeHex(link.context.traceId)),
      _encodeBytesField(2, _decodeHex(link.context.spanId)),
      if (link.context.traceState case final traceState?)
        _encodeStringField(3, traceState),
      _encodeRepeatedMessageField(4, _encodeAttributes(link.attributes)),
    ]);
  }

  static List<int> _encodeResourceMetrics(
    Resource resource,
    List<MetricData> metrics,
  ) {
    return _encodeMessage(<List<int>>[
      _encodeMessageField(1, _encodeResource(resource)),
      _encodeRepeatedMessageField(
        2,
        _groupByScope(metrics, _encodeScopeMetrics),
      ),
      if (resource.schemaUrl != null)
        _encodeStringField(3, resource.schemaUrl!),
    ]);
  }

  static List<int> _encodeScopeMetrics(
    InstrumentationScope scope,
    List<MetricData> metrics,
  ) {
    return _encodeMessage(<List<int>>[
      _encodeMessageField(1, _encodeScope(scope)),
      _encodeRepeatedMessageField(
        2,
        metrics.map(_encodeMetric).toList(growable: false),
      ),
      if (scope.schemaUrl != null) _encodeStringField(3, scope.schemaUrl!),
    ]);
  }

  static List<int> _encodeMetric(MetricData metric) {
    final fields = <List<int>>[
      _encodeStringField(1, metric.name),
      if (metric.description case final description?)
        _encodeStringField(2, description),
      if (metric.unit case final unit?) _encodeStringField(3, unit),
    ];

    switch (metric.instrumentType) {
      case MetricInstrumentType.counter:
      case MetricInstrumentType.observableCounter:
      case MetricInstrumentType.upDownCounter:
        fields.add(_encodeMessageField(7, _encodeSum(metric)));
      case MetricInstrumentType.observableGauge:
        fields.add(_encodeMessageField(5, _encodeGauge(metric)));
      case MetricInstrumentType.histogram:
        fields.add(_encodeMessageField(9, _encodeHistogram(metric)));
    }

    return _encodeMessage(fields);
  }

  static List<int> _encodeGauge(MetricData metric) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(
        1,
        metric.points.map(_encodeNumberDataPoint).toList(growable: false),
      ),
    ]);
  }

  static List<int> _encodeSum(MetricData metric) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(
        1,
        metric.points.map(_encodeNumberDataPoint).toList(growable: false),
      ),
      _encodeEnumField(2, _encodeTemporality(metric.aggregationTemporality)),
      _encodeBoolField(3, metric.isMonotonic ?? false),
    ]);
  }

  static List<int> _encodeHistogram(MetricData metric) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(
        1,
        metric.points.map(_encodeHistogramDataPoint).toList(growable: false),
      ),
      _encodeEnumField(2, _encodeTemporality(metric.aggregationTemporality)),
    ]);
  }

  static List<int> _encodeNumberDataPoint(MetricPoint point) {
    return _encodeMessage(<List<int>>[
      if (point.startTimestamp case final start?)
        _encodeFixed64Field(2, _toUnixNanos(start)),
      _encodeFixed64Field(3, _toUnixNanos(point.timestamp)),
      if (point.value != null)
        if (point.value is int)
          _encodeSfixed64Field(6, point.value!.toInt())
        else
          _encodeDoubleField(4, point.value!.toDouble()),
      _encodeRepeatedMessageField(7, _encodeAttributes(point.attributes)),
    ]);
  }

  static List<int> _encodeHistogramDataPoint(MetricPoint point) {
    return _encodeMessage(<List<int>>[
      if (point.startTimestamp case final start?)
        _encodeFixed64Field(2, _toUnixNanos(start)),
      _encodeFixed64Field(3, _toUnixNanos(point.timestamp)),
      _encodeFixed64Field(4, point.count ?? 0),
      if (point.sum case final sum?) _encodeDoubleField(5, sum),
      if ((point.bucketCounts ?? const <int>[]).isNotEmpty)
        _encodePackedFixed64Field(6, point.bucketCounts!),
      if ((point.explicitBounds ?? const <double>[]).isNotEmpty)
        _encodePackedDoubleField(7, point.explicitBounds!),
      _encodeRepeatedMessageField(9, _encodeAttributes(point.attributes)),
      if (point.min case final min?) _encodeDoubleField(11, min),
      if (point.max case final max?) _encodeDoubleField(12, max),
    ]);
  }

  static List<int> _encodeResourceLogs(
    Resource resource,
    List<LogRecord> logs,
  ) {
    return _encodeMessage(<List<int>>[
      _encodeMessageField(1, _encodeResource(resource)),
      _encodeRepeatedMessageField(2, _groupByScope(logs, _encodeScopeLogs)),
      if (resource.schemaUrl != null)
        _encodeStringField(3, resource.schemaUrl!),
    ]);
  }

  static List<int> _encodeScopeLogs(
    InstrumentationScope scope,
    List<LogRecord> logs,
  ) {
    return _encodeMessage(<List<int>>[
      _encodeMessageField(1, _encodeScope(scope)),
      _encodeRepeatedMessageField(
        2,
        logs.map(_encodeLogRecord).toList(growable: false),
      ),
      if (scope.schemaUrl != null) _encodeStringField(3, scope.schemaUrl!),
    ]);
  }

  static List<int> _encodeLogRecord(LogRecord log) {
    return _encodeMessage(<List<int>>[
      _encodeFixed64Field(1, _toUnixNanos(log.timestamp)),
      _encodeEnumField(2, log.severity.value),
      if (log.severityText case final severityText?)
        _encodeStringField(3, severityText),
      _encodeMessageField(5, _encodeAnyValue(log.body)),
      _encodeRepeatedMessageField(6, _encodeAttributes(log.attributes)),
      if (log.traceIdValue case final traceId?)
        _encodeBytesField(9, _decodeHex(traceId.hex)),
      if (log.spanIdValue case final spanId?)
        _encodeBytesField(10, _decodeHex(spanId.hex)),
      if (log.observedTimestamp case final observed?)
        _encodeFixed64Field(11, _toUnixNanos(observed)),
    ]);
  }

  static List<int> _encodeResource(Resource resource) {
    return _encodeMessage(<List<int>>[
      _encodeRepeatedMessageField(1, _encodeAttributes(resource.attributes)),
    ]);
  }

  static List<int> _encodeScope(InstrumentationScope scope) {
    return _encodeMessage(<List<int>>[
      _encodeStringField(1, scope.name),
      if (scope.version != null) _encodeStringField(2, scope.version!),
      _encodeRepeatedMessageField(3, _encodeAttributes(scope.attributes)),
    ]);
  }

  static List<List<int>> _encodeAttributes(Map<String, Object> attributes) {
    return attributes.entries
        .map(
          (entry) => _encodeMessage(<List<int>>[
            _encodeStringField(1, entry.key),
            _encodeMessageField(2, _encodeAnyValue(entry.value)),
          ]),
        )
        .toList(growable: false);
  }

  static List<int> _encodeAnyValue(Object value) {
    if (value is String) {
      return _encodeMessage(<List<int>>[_encodeStringField(1, value)]);
    }
    if (value is bool) {
      return _encodeMessage(<List<int>>[_encodeBoolField(2, value)]);
    }
    if (value is int) {
      return _encodeMessage(<List<int>>[_encodeInt64Field(3, value)]);
    }
    if (value is double) {
      return _encodeMessage(<List<int>>[_encodeDoubleField(4, value)]);
    }
    if (value is List) {
      return _encodeMessage(<List<int>>[
        _encodeMessageField(
          5,
          _encodeMessage(<List<int>>[
            _encodeRepeatedMessageField(
              1,
              value
                  .map((item) => _encodeAnyValue(item as Object))
                  .toList(growable: false),
            ),
          ]),
        ),
      ]);
    }
    return _encodeMessage(<List<int>>[_encodeStringField(1, value.toString())]);
  }

  static List<int> _encodeMessage(List<List<int>> fields) {
    final builder = BytesBuilder(copy: false);
    for (final field in fields) {
      builder.add(field);
    }
    return builder.toBytes();
  }

  static List<int> _encodeMessageField(int fieldNumber, List<int> message) {
    return _encodeLengthDelimitedField(fieldNumber, message);
  }

  static List<int> _encodeRepeatedMessageField(
    int fieldNumber,
    List<List<int>> messages,
  ) {
    final builder = BytesBuilder(copy: false);
    for (final message in messages) {
      builder.add(_encodeMessageField(fieldNumber, message));
    }
    return builder.toBytes();
  }

  static List<int> _encodeStringField(int fieldNumber, String value) {
    return _encodeLengthDelimitedField(fieldNumber, utf8.encode(value));
  }

  static List<int> _encodeBytesField(int fieldNumber, List<int> value) {
    return _encodeLengthDelimitedField(fieldNumber, value);
  }

  static List<int> _encodeLengthDelimitedField(
    int fieldNumber,
    List<int> value,
  ) {
    return _concat(<List<int>>[
      _encodeKey(fieldNumber, 2),
      _encodeVarint(value.length),
      value,
    ]);
  }

  static List<int> _encodeEnumField(int fieldNumber, int value) {
    return _encodeVarintField(fieldNumber, value);
  }

  static List<int> _encodeBoolField(int fieldNumber, bool value) {
    return _encodeVarintField(fieldNumber, value ? 1 : 0);
  }

  static List<int> _encodeVarintField(int fieldNumber, int value) {
    return _concat(<List<int>>[
      _encodeKey(fieldNumber, 0),
      _encodeVarint(value),
    ]);
  }

  static List<int> _encodeInt64Field(int fieldNumber, int value) {
    return _concat(<List<int>>[
      _encodeKey(fieldNumber, 0),
      _encodeSignedVarint64(value),
    ]);
  }

  static List<int> _encodeFixed64Field(int fieldNumber, int value) {
    return _concat(<List<int>>[
      _encodeKey(fieldNumber, 1),
      _fixed64Bytes(value),
    ]);
  }

  static List<int> _encodeSfixed64Field(int fieldNumber, int value) {
    return _encodeFixed64Field(fieldNumber, value);
  }

  static List<int> _encodeDoubleField(int fieldNumber, double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    return _concat(<List<int>>[
      _encodeKey(fieldNumber, 1),
      data.buffer.asUint8List(),
    ]);
  }

  static List<int> _encodePackedFixed64Field(
    int fieldNumber,
    List<int> values,
  ) {
    final data = BytesBuilder(copy: false);
    for (final value in values) {
      data.add(_fixed64Bytes(value));
    }
    return _encodeLengthDelimitedField(fieldNumber, data.toBytes());
  }

  static List<int> _encodePackedDoubleField(
    int fieldNumber,
    List<double> values,
  ) {
    final data = BytesBuilder(copy: false);
    for (final value in values) {
      final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
      data.add(bytes.buffer.asUint8List());
    }
    return _encodeLengthDelimitedField(fieldNumber, data.toBytes());
  }

  static List<int> _encodeKey(int fieldNumber, int wireType) {
    return _encodeVarint((fieldNumber << 3) | wireType);
  }

  static List<int> _encodeVarint(int value) {
    return _encodeVarintBigInt(BigInt.from(value));
  }

  static List<int> _encodeSignedVarint64(int value) {
    final bigValue = BigInt.from(value);
    if (value >= 0) {
      return _encodeVarintBigInt(bigValue);
    }

    final masked = bigValue & _uint64Mask;
    return _encodeVarintBigInt(masked);
  }

  static List<int> _encodeVarintBigInt(BigInt value) {
    final bytes = <int>[];
    var remaining = value;
    while (remaining > _sevenBitMask) {
      bytes.add(((remaining & _sevenBitMask).toInt()) | 0x80);
      remaining = remaining >> 7;
    }
    bytes.add(remaining.toInt());
    return bytes;
  }

  static List<int> _fixed64Bytes(int value) {
    final masked = BigInt.from(value) & _uint64Mask;
    final data = ByteData(8);
    var remaining = masked;
    for (var index = 0; index < 8; index += 1) {
      data.setUint8(index, (remaining & BigInt.from(0xff)).toInt());
      remaining = remaining >> 8;
    }
    return data.buffer.asUint8List();
  }

  static List<int> _concat(List<List<int>> parts) {
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part);
    }
    return builder.toBytes();
  }

  static List<int> _decodeHex(String hex) {
    final normalized = hex.length.isOdd ? '0$hex' : hex;
    return <int>[
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ];
  }

  static int _toUnixNanos(DateTime timestamp) {
    return timestamp.toUtc().microsecondsSinceEpoch * 1000;
  }

  static int _encodeSpanKind(String kind) {
    switch (kind) {
      case 'internal':
        return 1;
      case 'server':
        return 2;
      case 'client':
        return 3;
      case 'producer':
        return 4;
      case 'consumer':
        return 5;
      default:
        return 0;
    }
  }

  static int _encodeStatusCode(String status) {
    switch (status) {
      case 'ok':
        return 1;
      case 'error':
        return 2;
      default:
        return 0;
    }
  }

  static int _encodeTemporality(AggregationTemporality temporality) {
    switch (temporality) {
      case AggregationTemporality.delta:
        return 1;
      case AggregationTemporality.cumulative:
        return 2;
      case AggregationTemporality.unspecified:
        return 0;
    }
  }

  static final BigInt _sevenBitMask = BigInt.from(0x7f);
  static final BigInt _uint64Mask = (BigInt.one << 64) - BigInt.one;
}
