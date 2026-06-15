part of '../comon_otel_test.dart';

final class _RecordedRequest {
  const _RecordedRequest(this.request);

  final OtlpHttpRequest request;
}

final class _FakeOtlpHttpTransport implements OtlpHttpTransport {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Future<OtlpHttpResponse> postJson(OtlpHttpRequest request) async {
    requests.add(_RecordedRequest(request));
    return const OtlpHttpResponse(statusCode: 200, body: '{}');
  }

  @override
  Future<OtlpHttpResponse> postBytes(OtlpHttpRequest request) async {
    requests.add(_RecordedRequest(request));
    return const OtlpHttpResponse(statusCode: 200, body: '{}');
  }

  @override
  Future<void> shutdown() async {}
}

final class _SequencedOtlpHttpTransport implements OtlpHttpTransport {
  _SequencedOtlpHttpTransport(this.responses);

  final List<Object> responses;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Future<OtlpHttpResponse> postJson(OtlpHttpRequest request) async {
    requests.add(_RecordedRequest(request));
    final next = responses.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    return next as OtlpHttpResponse;
  }

  @override
  Future<OtlpHttpResponse> postBytes(OtlpHttpRequest request) async {
    requests.add(_RecordedRequest(request));
    final next = responses.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    return next as OtlpHttpResponse;
  }

  @override
  Future<void> shutdown() async {}
}

final class _SignalAwareOtlpHttpTransport implements OtlpHttpTransport {
  _SignalAwareOtlpHttpTransport(this.responsesBySignal);

  final Map<String, List<Object>> responsesBySignal;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Future<OtlpHttpResponse> postJson(OtlpHttpRequest request) async {
    return _post(request);
  }

  @override
  Future<OtlpHttpResponse> postBytes(OtlpHttpRequest request) async {
    return _post(request);
  }

  Future<OtlpHttpResponse> _post(OtlpHttpRequest request) async {
    requests.add(_RecordedRequest(request));
    final signal = _resolveSignal(request.body);
    final responses = responsesBySignal[signal]!;
    final next = responses.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    return next as OtlpHttpResponse;
  }

  @override
  Future<void> shutdown() async {}

  String _resolveSignal(String body) {
    if (body.contains('resourceSpans')) {
      return 'traces';
    }
    if (body.contains('resourceMetrics')) {
      return 'metrics';
    }
    if (body.contains('resourceLogs')) {
      return 'logs';
    }
    if (requests.last.request.uri.path.endsWith('/v1/traces')) {
      return 'traces';
    }
    if (requests.last.request.uri.path.endsWith('/v1/metrics')) {
      return 'metrics';
    }
    if (requests.last.request.uri.path.endsWith('/v1/logs')) {
      return 'logs';
    }
    throw StateError('Unknown OTLP payload family: $body');
  }
}

final class _RecordedGrpcRequest {
  const _RecordedGrpcRequest(this.request);

  final OtlpGrpcRequest request;
}

final class _FakeOtlpGrpcTransport implements OtlpGrpcTransport {
  final List<_RecordedGrpcRequest> requests = <_RecordedGrpcRequest>[];

  @override
  Future<List<int>> export(OtlpGrpcRequest request) async {
    requests.add(_RecordedGrpcRequest(request));
    return const <int>[];
  }

  @override
  Future<void> shutdown() async {}
}

final class _SequencedOtlpGrpcTransport implements OtlpGrpcTransport {
  _SequencedOtlpGrpcTransport(this.responses);

  final List<Object> responses;
  final List<_RecordedGrpcRequest> requests = <_RecordedGrpcRequest>[];

  @override
  Future<List<int>> export(OtlpGrpcRequest request) async {
    requests.add(_RecordedGrpcRequest(request));
    final next = responses.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    if (next is List<int>) {
      return next;
    }
    return const <int>[];
  }

  @override
  Future<void> shutdown() async {}
}

final class _SignalAwareOtlpGrpcTransport implements OtlpGrpcTransport {
  _SignalAwareOtlpGrpcTransport(this.responsesBySignal);

  final Map<OtlpSignal, List<Object>> responsesBySignal;
  final List<_RecordedGrpcRequest> requests = <_RecordedGrpcRequest>[];

  @override
  Future<List<int>> export(OtlpGrpcRequest request) async {
    requests.add(_RecordedGrpcRequest(request));
    final responses = responsesBySignal[request.signal]!;
    final next = responses.removeAt(0);
    if (next is Exception) {
      throw next;
    }
    if (next is List<int>) {
      return next;
    }
    return const <int>[];
  }

  @override
  Future<void> shutdown() async {}
}

final class _FailingSpanExporter implements SpanExporter {
  @override
  Future<ExportResult> export(List<SpanData> spans) async {
    return ExportResult.failure;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

final class _FailingMetricExporter implements MetricExporter {
  @override
  Future<ExportResult> export(List<MetricData> metrics) async {
    return ExportResult.failure;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

final class _FailingLogExporter implements LogExporter {
  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    return ExportResult.failure;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

final class _ThrowOnceSpanExporter implements SpanExporter {
  int exportCalls = 0;
  final List<SpanData> exported = <SpanData>[];

  @override
  Future<ExportResult> export(List<SpanData> spans) async {
    exportCalls += 1;
    if (exportCalls == 1) {
      throw TimeoutException('simulated export timeout');
    }
    exported.addAll(spans);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

final class _ThrowOnceLogExporter implements LogExporter {
  int exportCalls = 0;
  final List<LogRecord> exported = <LogRecord>[];

  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    exportCalls += 1;
    if (exportCalls == 1) {
      throw TimeoutException('simulated export timeout');
    }
    exported.addAll(logs);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

final class _StaticResourceDetector implements ResourceDetector {
  const _StaticResourceDetector(this.attributes);

  final Map<String, Object> attributes;

  @override
  Map<String, Object> detect() => attributes;
}

final class _DelayedSpanExporter implements SpanExporter {
  final List<Completer<ExportResult>> _completers = <Completer<ExportResult>>[];
  int forceFlushCount = 0;

  int get pendingCount =>
      _completers.where((completer) => !completer.isCompleted).length;

  @override
  Future<ExportResult> export(List<SpanData> spans) {
    final completer = Completer<ExportResult>();
    _completers.add(completer);
    return completer.future;
  }

  void completeAll([ExportResult result = ExportResult.success]) {
    for (final completer in _completers) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }
  }

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}

final class _DelayedLogExporter implements LogExporter {
  final List<Completer<ExportResult>> _completers = <Completer<ExportResult>>[];
  int forceFlushCount = 0;

  int get pendingCount =>
      _completers.where((completer) => !completer.isCompleted).length;

  @override
  Future<ExportResult> export(List<LogRecord> logs) {
    final completer = Completer<ExportResult>();
    _completers.add(completer);
    return completer.future;
  }

  void completeAll([ExportResult result = ExportResult.success]) {
    for (final completer in _completers) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }
  }

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}

final class _TraceStateInjectingSampler implements Sampler {
  const _TraceStateInjectingSampler(this.traceState);

  final TraceState traceState;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return SamplerResult(sampled: true, traceState: traceState);
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return true;
  }
}

final class _LinkCapturingSampler implements Sampler {
  const _LinkCapturingSampler(this.onDecide);

  final void Function(List<SpanLink>? links) onDecide;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    onDecide(links);
    return SamplerResult(
      sampled: true,
      traceState:
          parentSnapshot?.traceStateValue ?? parentContext?.traceStateValue,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return true;
  }
}

final class _SnapshotCapturingSampler implements Sampler {
  const _SnapshotCapturingSampler(this.onDecide);

  final void Function(OtelContextSnapshot? snapshot) onDecide;

  @override
  SamplerResult decide({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    onDecide(parentSnapshot);
    return SamplerResult(
      sampled: true,
      traceState:
          parentSnapshot?.traceStateValue ?? parentContext?.traceStateValue,
    );
  }

  @override
  bool shouldSample({
    required TraceId traceId,
    required String name,
    required SpanKind kind,
    OtelContextSnapshot? parentSnapshot,
    SpanContext? parentContext,
    Map<String, Object>? attributes,
    List<SpanLink>? links,
  }) {
    return true;
  }
}

final class _RecordingSpanProcessor implements SpanProcessor {
  final List<Span> started = <Span>[];
  final List<Span> ended = <Span>[];

  @override
  void onStart(Span span) {
    started.add(span);
  }

  @override
  void onEnd(Span span) {
    ended.add(span);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

Map<String, String> _parseOtelMembers(String value) {
  final members = <String, String>{};

  for (final rawMember in value.split(';')) {
    final member = rawMember.trim();
    if (member.isEmpty) {
      continue;
    }

    final separatorIndex = member.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex == member.length - 1) {
      continue;
    }

    members[member.substring(0, separatorIndex)] = member.substring(
      separatorIndex + 1,
    );
  }

  return members;
}

final class _TestRepository with OtelDatabaseMixin {
  @override
  String get dbName => 'test.db';

  @override
  String get dbSystem => 'sqlite';

  @override
  Duration get slowQueryThreshold => Duration.zero;
}

final class _TestLogExtension extends OtelLogExtension {
  @override
  String get defaultLoggerName => 'test.bridge';

  @override
  SeverityNumber mapSeverity(String level) {
    switch (level) {
      case 'DEBUG':
        return SeverityNumber.debug;
      case 'WARN':
        return SeverityNumber.warn;
      case 'ERROR':
        return SeverityNumber.error;
      default:
        return SeverityNumber.info;
    }
  }
}

List<int> _encodePartialSuccessResponse({
  required int rejectedCount,
  required String errorMessage,
}) {
  final errorBytes = utf8.encode(errorMessage);
  final partialSuccess = <int>[
    0x08,
    rejectedCount,
    0x12,
    errorBytes.length,
    ...errorBytes,
  ];

  return <int>[0x0a, partialSuccess.length, ...partialSuccess];
}

Map<String, Object?> _decodeAttributes(List<Object?> attributes) {
  return <String, Object?>{
    for (final attribute in attributes.cast<Map<String, Object?>>())
      attribute['key']! as String: _decodeAnyValue(
        attribute['value'] as Map<String, Object?>,
      ),
  };
}

Object? _decodeAnyValue(Map<String, Object?> value) {
  if (value.containsKey('stringValue')) {
    return value['stringValue'];
  }
  if (value.containsKey('boolValue')) {
    return value['boolValue'];
  }
  if (value.containsKey('intValue')) {
    return value['intValue'];
  }
  if (value.containsKey('doubleValue')) {
    return value['doubleValue'];
  }
  if (value.containsKey('arrayValue')) {
    final arrayValue = value['arrayValue'] as Map<String, Object?>;
    final values =
        (arrayValue['values'] as List<Object?>?) ?? const <Object?>[];
    return values
        .cast<Map<String, Object?>>()
        .map(_decodeAnyValue)
        .toList(growable: false);
  }
  if (value.containsKey('kvlistValue')) {
    final kvlistValue = value['kvlistValue'] as Map<String, Object?>;
    final values =
        (kvlistValue['values'] as List<Object?>?) ?? const <Object?>[];
    return _decodeAttributes(values);
  }
  if (value.containsKey('bytesValue')) {
    return value['bytesValue'];
  }
  return null;
}
