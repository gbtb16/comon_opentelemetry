part of '../otlp_collector_integration_test.dart';

const String _collectorImage = 'otel/opentelemetry-collector-contrib:latest';
const String _linkedTraceId = '4bf92f3577b34da6a3ce929d0e0e4736';
const String _linkedSpanId = '00f067aa0ba902b7';
final Object _dockerRequirement = _resolveDockerRequirement();

final class _CapturedHttpRequest {
  const _CapturedHttpRequest({
    required this.path,
    required this.headers,
    required this.bodyBytes,
  });

  final String path;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

final class _HttpCaptureServer {
  _HttpCaptureServer._({required this.server, required this.responseDelay});

  final HttpServer server;
  final Duration responseDelay;
  final List<_CapturedHttpRequest> requests = <_CapturedHttpRequest>[];

  int get port => server.port;

  static Future<_HttpCaptureServer> start({
    Duration responseDelay = Duration.zero,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final capture = _HttpCaptureServer._(
      server: server,
      responseDelay: responseDelay,
    );
    unawaited(capture._serve());
    return capture;
  }

  Future<void> _serve() async {
    await for (final request in server) {
      final bodyBytes = await _readRequestBytes(request);
      requests.add(
        _CapturedHttpRequest(
          path: request.uri.path,
          headers: () {
            final headers = <String, String>{};
            request.headers.forEach((name, values) {
              headers[name] = values.join(',');
            });
            return headers;
          }(),
          bodyBytes: bodyBytes,
        ),
      );
      if (responseDelay > Duration.zero) {
        await Future<void>.delayed(responseDelay);
      }
      request.response.statusCode = 200;
      request.response.write('{}');
      await request.response.close();
    }
  }

  Future<void> close() => server.close(force: true);
}

Object _resolveDockerRequirement() {
  try {
    final result = Process.runSync('docker', <String>[
      'version',
      '--format',
      '{{.Server.Version}}',
    ]);
    if (result.exitCode == 0) {
      return false;
    }
  } on ProcessException {
    // Fall through to a skipped test reason below.
  }

  return 'Docker daemon is required for collector integration tests.';
}

final class _CollectorHarness {
  _CollectorHarness({
    required this.rootDir,
    required this.outputDir,
    required this.containerName,
    required this.volumeName,
    required this.grpcPort,
    required this.httpPort,
    required this.healthPort,
  });

  final Directory rootDir;
  final Directory outputDir;
  final String containerName;
  final String volumeName;
  final int grpcPort;
  final int httpPort;
  final int healthPort;

  static Future<_CollectorHarness> start() async {
    return startWithPorts();
  }

  static Future<_CollectorHarness> startWithPorts({
    int? grpcPort,
    int? httpPort,
    int? healthPort,
  }) async {
    final rootDir = await Directory.systemTemp.createTemp(
      'comon_otel_collector_',
    );
    final outputDir = Directory('${rootDir.path}${Platform.pathSeparator}out');
    await outputDir.create(recursive: true);

    grpcPort ??= await _allocatePort();
    httpPort ??= await _allocatePort();
    healthPort ??= await _allocatePort();
    final containerName =
        'comon-otel-it-${DateTime.now().microsecondsSinceEpoch}';
    final volumeName =
        'comon-otel-it-${DateTime.now().microsecondsSinceEpoch}-data';

    final configFile = File(
      '${rootDir.path}${Platform.pathSeparator}collector.yaml',
    );
    await configFile.writeAsString(_collectorConfig);

    final createVolumeResult = await Process.run('docker', <String>[
      'volume',
      'create',
      volumeName,
    ]);
    if (createVolumeResult.exitCode != 0) {
      await rootDir.delete(recursive: true);
      throw StateError(
        'Failed to create collector volume: ${createVolumeResult.stderr}',
      );
    }

    final result = await Process.run('docker', <String>[
      'run',
      '-d',
      '--name',
      containerName,
      '--user',
      '0:0',
      '--mount',
      'type=bind,source=${_dockerPath(configFile.path)},target=/etc/otelcol-contrib/config.yaml,readonly',
      '--mount',
      'type=volume,source=$volumeName,target=/data',
      '-p',
      '$grpcPort:4317',
      '-p',
      '$httpPort:4318',
      '-p',
      '$healthPort:13133',
      _collectorImage,
    ]);

    if (result.exitCode != 0) {
      await Process.run('docker', <String>['volume', 'rm', '-f', volumeName]);
      await rootDir.delete(recursive: true);
      throw StateError('Failed to start collector container: ${result.stderr}');
    }

    final harness = _CollectorHarness(
      rootDir: rootDir,
      outputDir: outputDir,
      containerName: containerName,
      volumeName: volumeName,
      grpcPort: grpcPort,
      httpPort: httpPort,
      healthPort: healthPort,
    );
    await harness._waitUntilHealthy();
    return harness;
  }

  Future<void> dispose() async {
    await Process.run('docker', <String>['rm', '-f', containerName]);
    await Process.run('docker', <String>['volume', 'rm', '-f', volumeName]);
    if (await rootDir.exists()) {
      await rootDir.delete(recursive: true);
    }
  }

  Future<List<Map<String, Object?>>> waitForSignal(String fileName) async {
    final file = File('${outputDir.path}${Platform.pathSeparator}$fileName');
    final deadline = DateTime.now().add(const Duration(seconds: 20));

    while (DateTime.now().isBefore(deadline)) {
      final copyResult = await Process.run('docker', <String>[
        'cp',
        '$containerName:/data/$fileName',
        file.path,
      ]);

      if (copyResult.exitCode == 0 && await file.exists()) {
        final content = await file.readAsString();
        final lines = content
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList(growable: false);
        if (lines.isNotEmpty) {
          return lines
              .map((line) => jsonDecode(line) as Map<String, Object?>)
              .toList(growable: false);
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final logs = await collectorLogs();
    throw StateError('Timed out waiting for $fileName. Collector logs:\n$logs');
  }

  Future<String> collectorLogs() async {
    final result = await Process.run('docker', <String>['logs', containerName]);
    return '${result.stdout}\n${result.stderr}'.trim();
  }

  Future<void> _waitUntilHealthy() async {
    final client = HttpClient();
    final deadline = DateTime.now().add(const Duration(seconds: 30));

    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$healthPort/'),
          );
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == 200) {
            return;
          }
        } catch (_) {
          // Retry until the collector is ready or the deadline expires.
        }

        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      throw StateError(
        'Collector did not become healthy in time. Logs:\n${await collectorLogs()}',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<int> _allocatePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static String _dockerPath(String path) => path.replaceAll('\\', '/');

  static const String _collectorConfig = '''
extensions:
  health_check:
    endpoint: 0.0.0.0:13133

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 100ms

exporters:
  file/traces:
    path: /data/traces.json
    format: json
    append: true
    flush_interval: 100ms
  file/metrics:
    path: /data/metrics.json
    format: json
    append: true
    flush_interval: 100ms
  file/logs:
    path: /data/logs.json
    format: json
    append: true
    flush_interval: 100ms

service:
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [file/traces]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [file/metrics]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [file/logs]
''';
}

Future<void> _emitIntegrationScenario({
  required OtelExporter exporter,
  required String endpoint,
  required String protocolLabel,
  String? resourceSchemaUrl,
  String? traceScopeSchemaUrl,
  String? metricScopeSchemaUrl,
  String? tracesEndpoint,
  String? metricsEndpoint,
  String? logsEndpoint,
  Map<String, String>? otlpHeaders,
  Map<String, String>? otlpTracesHeaders,
  Map<String, String>? otlpMetricsHeaders,
  Map<String, String>? otlpLogsHeaders,
  Duration otlpTimeout = const Duration(seconds: 5),
  Duration? otlpTracesTimeout,
  Duration? otlpMetricsTimeout,
  Duration? otlpLogsTimeout,
  OtlpCompression otlpCompression = OtlpCompression.gzip,
  OtlpCompression? otlpTracesCompression,
  OtlpCompression? otlpMetricsCompression,
  OtlpCompression? otlpLogsCompression,
  OtlpRetryConfig otlpRetry = const OtlpRetryConfig(),
  OtlpRetryConfig? otlpTracesRetry,
  OtlpRetryConfig? otlpMetricsRetry,
  OtlpRetryConfig? otlpLogsRetry,
}) async {
  await Otel.shutdown();
  await Otel.init(
    serviceName: 'collector-it',
    resourceSchemaUrl: resourceSchemaUrl,
    endpoint: endpoint,
    tracesEndpoint: tracesEndpoint,
    metricsEndpoint: metricsEndpoint,
    logsEndpoint: logsEndpoint,
    environment: 'integration',
    exporter: exporter,
    otlpHeaders: otlpHeaders,
    otlpTracesHeaders: otlpTracesHeaders,
    otlpMetricsHeaders: otlpMetricsHeaders,
    otlpLogsHeaders: otlpLogsHeaders,
    otlpCompression: otlpCompression,
    otlpTracesCompression: otlpTracesCompression,
    otlpMetricsCompression: otlpMetricsCompression,
    otlpLogsCompression: otlpLogsCompression,
    otlpTimeout: otlpTimeout,
    otlpTracesTimeout: otlpTracesTimeout,
    otlpMetricsTimeout: otlpMetricsTimeout,
    otlpLogsTimeout: otlpLogsTimeout,
    otlpRetry: otlpRetry,
    otlpTracesRetry: otlpTracesRetry,
    otlpMetricsRetry: otlpMetricsRetry,
    otlpLogsRetry: otlpLogsRetry,
    resourceAttributes: <String, Object>{
      'service.version': 'it-1.0.0',
      'test.case': protocolLabel,
    },
  );

  final tracer = traceScopeSchemaUrl == null
      ? Otel.instance.tracer
      : Otel.instance.tracerProvider.getTracer(
          'collector.integration.tracer',
          version: '1.0.0',
          schemaUrl: traceScopeSchemaUrl,
        );
  final meter = metricScopeSchemaUrl == null
      ? Otel.instance.meter
      : Otel.instance.meterProvider.getMeter(
          'collector.integration.meter',
          version: '1.0.0',
          schemaUrl: metricScopeSchemaUrl,
        );

  final counter = meter.createIntCounter('integration.requests');
  final histogram = meter.createHistogram(
    'integration.duration',
    boundaries: <double>[10, 50, 100],
  );

  counter.add(
    2,
    attributes: <String, Object>{
      'route': '/checkout',
      'protocol': protocolLabel,
    },
  );
  histogram.record(
    42.5,
    attributes: <String, Object>{
      'route': '/checkout',
      'protocol': protocolLabel,
    },
  );

  final link = SpanLink(
    context: SpanContext.remote(
      traceId: const TraceId(_linkedTraceId),
      spanId: const SpanId(_linkedSpanId),
      traceFlags: TraceFlags.sampled,
      traceState: const TraceState('vendor=test'),
    ),
    attributes: <String, Object>{'link.type': 'remote-parent'},
  );

  await tracer.traceAsync(
    'collector-parent',
    kind: SpanKind.server,
    attributes: <String, Object>{'component': 'integration'},
    fn: () async {
      final child = tracer.startSpan(
        'collector-child',
        kind: SpanKind.client,
        attributes: <String, Object>{
          'db.system': 'postgresql',
          'db.operation': 'SELECT',
        },
        links: <SpanLink>[link],
      );

      await OtelContext.withSpan(child, () async {
        child.addEvent(
          'db.query',
          attributes: <String, Object>{'rows': 2, 'cached': false},
        );

        try {
          throw StateError('collector boom');
        } catch (error, stackTrace) {
          child.recordException(error, stackTrace: stackTrace);
          child.setStatus(SpanStatus.error, description: error.toString());
        }

        Otel.instance.logger.error(
          'collector-log',
          attributes: <String, Object>{
            'protocol': protocolLabel,
            'phase': 'child',
          },
          error: StateError('log boom'),
        );
      });

      await child.end();
    },
  );

  await Otel.forceFlush();
  await Future<void>.delayed(const Duration(seconds: 1));
  await Otel.shutdown();
}

Future<List<int>> _readRequestBytes(HttpRequest request) async {
  final chunks = <int>[];
  await for (final chunk in request) {
    chunks.addAll(chunk);
  }
  return chunks;
}

List<int> _maybeGunzip(_CapturedHttpRequest request) {
  final encoding = request.headers['content-encoding'];
  if (encoding == 'gzip') {
    return gzip.decode(request.bodyBytes);
  }
  return request.bodyBytes;
}

Future<void> _waitForRequestCount(
  _HttpCaptureServer server,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (server.requests.length >= expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Timed out waiting for $expected requests, got ${server.requests.length}.',
  );
}

List<Map<String, Object?>> _extractSpans(List<Map<String, Object?>> batches) {
  final spans = <Map<String, Object?>>[];

  for (final batch in batches) {
    final resourceSpans =
        batch['resourceSpans'] as List<Object?>? ?? const <Object?>[];
    for (final resourceSpan in resourceSpans) {
      final resourceSpanMap = resourceSpan as Map<String, Object?>;
      final resourceAttributes = _decodeAttributes(
        ((resourceSpanMap['resource'] as Map<String, Object?>?)?['attributes']
                as List<Object?>?) ??
            const <Object?>[],
      );
      final scopeSpans =
          resourceSpanMap['scopeSpans'] as List<Object?>? ?? const <Object?>[];
      for (final scopeSpan in scopeSpans) {
        final scopeSpanMap = scopeSpan as Map<String, Object?>;
        final scopeName =
            ((scopeSpanMap['scope'] as Map<String, Object?>?)?['name']
                as String?) ??
            'default';
        final batchSpans =
            scopeSpanMap['spans'] as List<Object?>? ?? const <Object?>[];
        for (final span in batchSpans) {
          spans.add(<String, Object?>{
            ...(span as Map<String, Object?>),
            '_resourceAttributes': resourceAttributes,
            '_resourceSchemaUrl': resourceSpanMap['schemaUrl'],
            '_scopeName': scopeName,
            '_scopeSchemaUrl': scopeSpanMap['schemaUrl'],
          });
        }
      }
    }
  }

  return spans;
}

List<Map<String, Object?>> _extractMetrics(List<Map<String, Object?>> batches) {
  final metrics = <Map<String, Object?>>[];

  for (final batch in batches) {
    final resourceMetrics =
        batch['resourceMetrics'] as List<Object?>? ?? const <Object?>[];
    for (final resourceMetric in resourceMetrics) {
      final resourceMetricMap = resourceMetric as Map<String, Object?>;
      final resourceAttributes = _decodeAttributes(
        ((resourceMetricMap['resource'] as Map<String, Object?>?)?['attributes']
                as List<Object?>?) ??
            const <Object?>[],
      );
      final scopeMetrics =
          resourceMetricMap['scopeMetrics'] as List<Object?>? ??
          const <Object?>[];
      for (final scopeMetric in scopeMetrics) {
        final scopeMetricMap = scopeMetric as Map<String, Object?>;
        final scopeName =
            ((scopeMetricMap['scope'] as Map<String, Object?>?)?['name']
                as String?) ??
            'default';
        final batchMetrics =
            scopeMetricMap['metrics'] as List<Object?>? ?? const <Object?>[];
        for (final metric in batchMetrics) {
          metrics.add(<String, Object?>{
            ...(metric as Map<String, Object?>),
            '_resourceAttributes': resourceAttributes,
            '_resourceSchemaUrl': resourceMetricMap['schemaUrl'],
            '_scopeName': scopeName,
            '_scopeSchemaUrl': scopeMetricMap['schemaUrl'],
          });
        }
      }
    }
  }

  return metrics;
}

List<Map<String, Object?>> _extractLogs(List<Map<String, Object?>> batches) {
  final logs = <Map<String, Object?>>[];

  for (final batch in batches) {
    final resourceLogs =
        batch['resourceLogs'] as List<Object?>? ?? const <Object?>[];
    for (final resourceLog in resourceLogs) {
      final resourceLogMap = resourceLog as Map<String, Object?>;
      final resourceAttributes = _decodeAttributes(
        ((resourceLogMap['resource'] as Map<String, Object?>?)?['attributes']
                as List<Object?>?) ??
            const <Object?>[],
      );
      final scopeLogs =
          resourceLogMap['scopeLogs'] as List<Object?>? ?? const <Object?>[];
      for (final scopeLog in scopeLogs) {
        final scopeLogMap = scopeLog as Map<String, Object?>;
        final scopeName =
            ((scopeLogMap['scope'] as Map<String, Object?>?)?['name']
                as String?) ??
            'default';
        final batchLogs =
            scopeLogMap['logRecords'] as List<Object?>? ?? const <Object?>[];
        for (final log in batchLogs) {
          logs.add(<String, Object?>{
            ...(log as Map<String, Object?>),
            '_resourceAttributes': resourceAttributes,
            '_resourceSchemaUrl': resourceLogMap['schemaUrl'],
            '_scopeName': scopeName,
            '_scopeSchemaUrl': scopeLogMap['schemaUrl'],
          });
        }
      }
    }
  }

  return logs;
}

Map<String, Object?> _decodeAttributes(List<Object?> attributes) {
  final decoded = <String, Object?>{};
  for (final attribute in attributes) {
    final attributeMap = attribute as Map<String, Object?>;
    decoded[attributeMap['key']! as String] = _decodeAnyValue(
      attributeMap['value'] as Map<String, Object?>,
    );
  }
  return decoded;
}

Object? _decodeAnyValue(Map<String, Object?> value) {
  if (value.containsKey('stringValue')) {
    return value['stringValue'];
  }
  if (value.containsKey('boolValue')) {
    return value['boolValue'];
  }
  if (value.containsKey('intValue')) {
    return int.tryParse(value['intValue'].toString()) ?? value['intValue'];
  }
  if (value.containsKey('doubleValue')) {
    return (value['doubleValue'] as num).toDouble();
  }
  if (value.containsKey('arrayValue')) {
    final items =
        ((value['arrayValue'] as Map<String, Object?>)['values']
            as List<Object?>?) ??
        const <Object?>[];
    return items
        .map((item) => _decodeAnyValue(item as Map<String, Object?>))
        .toList(growable: false);
  }
  return value;
}

void _assertRoundTrip(
  String protocolLabel, {
  required List<Map<String, Object?>> traceBatches,
  required List<Map<String, Object?>> metricBatches,
  required List<Map<String, Object?>> logBatches,
  String? expectedResourceSchemaUrl,
  String? expectedTraceScopeSchemaUrl,
  String? expectedMetricScopeSchemaUrl,
}) {
  final spans = _extractSpans(traceBatches);
  final parent = spans.singleWhere(
    (span) => span['name'] == 'collector-parent',
  );
  final child = spans.singleWhere((span) => span['name'] == 'collector-child');
  final childResource = child['_resourceAttributes']! as Map<String, Object?>;

  expect(childResource['service.name'], 'collector-it');
  expect(childResource['service.version'], 'it-1.0.0');
  expect(childResource['deployment.environment'], 'integration');
  expect(childResource['test.case'], protocolLabel);
  if (expectedResourceSchemaUrl != null) {
    expect(child['_resourceSchemaUrl'], expectedResourceSchemaUrl);
  }
  expect(child['traceId'], parent['traceId']);
  expect(child['parentSpanId'], parent['spanId']);
  if (expectedTraceScopeSchemaUrl != null) {
    expect(child['_scopeSchemaUrl'], expectedTraceScopeSchemaUrl);
    expect(child['_scopeName'], 'collector.integration.tracer');
  }

  final childAttributes = _decodeAttributes(
    child['attributes'] as List<Object?>? ?? const <Object?>[],
  );
  expect(childAttributes['db.system'], 'postgresql');
  expect(childAttributes['db.operation'], 'SELECT');

  final childLinks = child['links'] as List<Object?>? ?? const <Object?>[];
  expect(childLinks, hasLength(1));
  final link = childLinks.single as Map<String, Object?>;
  final linkAttributes = _decodeAttributes(
    link['attributes'] as List<Object?>? ?? const <Object?>[],
  );
  expect(link['traceId'], _linkedTraceId);
  expect(link['spanId'], _linkedSpanId);
  expect(link['traceState'], 'vendor=test');
  expect(linkAttributes['link.type'], 'remote-parent');

  final events = child['events'] as List<Object?>? ?? const <Object?>[];
  final eventNames = events
      .map((event) => (event as Map<String, Object?>)['name'])
      .toList(growable: false);
  expect(eventNames, containsAll(<Object?>['db.query', 'exception']));

  final status = child['status']! as Map<String, Object?>;
  expect(status['code'], 2);
  expect(status['message'], contains('collector boom'));

  final logs = _extractLogs(logBatches);
  final log = logs.singleWhere((entry) {
    final body = entry['body'] as Map<String, Object?>?;
    return body?['stringValue'] == 'collector-log';
  });
  if (expectedResourceSchemaUrl != null) {
    expect(log['_resourceSchemaUrl'], expectedResourceSchemaUrl);
  }
  final logAttributes = _decodeAttributes(
    log['attributes'] as List<Object?>? ?? const <Object?>[],
  );
  expect(log['severityText'], 'ERROR');
  expect(log['traceId'], child['traceId']);
  expect(log['spanId'], child['spanId']);
  expect(logAttributes['protocol'], protocolLabel);
  expect(logAttributes['phase'], 'child');
  expect(
    logAttributes[SemanticAttributes.exceptionMessage],
    contains('log boom'),
  );

  final metrics = _extractMetrics(metricBatches);
  final counter = metrics.singleWhere(
    (metric) => metric['name'] == 'integration.requests',
  );
  if (expectedResourceSchemaUrl != null) {
    expect(counter['_resourceSchemaUrl'], expectedResourceSchemaUrl);
  }
  if (expectedMetricScopeSchemaUrl != null) {
    expect(counter['_scopeSchemaUrl'], expectedMetricScopeSchemaUrl);
    expect(counter['_scopeName'], 'collector.integration.meter');
  }
  final counterSum = counter['sum']! as Map<String, Object?>;
  final counterPoint =
      (counterSum['dataPoints'] as List<Object?>).single
          as Map<String, Object?>;
  final counterAttributes = _decodeAttributes(
    counterPoint['attributes'] as List<Object?>? ?? const <Object?>[],
  );
  expect(counterPoint['asInt'].toString(), '2');
  expect(counterAttributes['route'], '/checkout');
  expect(counterAttributes['protocol'], protocolLabel);

  final histogram = metrics.singleWhere(
    (metric) => metric['name'] == 'integration.duration',
  );
  final histogramPayload = histogram['histogram']! as Map<String, Object?>;
  final histogramPoint =
      (histogramPayload['dataPoints'] as List<Object?>).single
          as Map<String, Object?>;
  final histogramAttributes = _decodeAttributes(
    histogramPoint['attributes'] as List<Object?>? ?? const <Object?>[],
  );
  expect(histogramPoint['count'].toString(), '1');
  expect((histogramPoint['sum'] as num).toDouble(), closeTo(42.5, 0.001));
  expect(histogramPoint['bucketCounts'], isNotEmpty);
  expect(histogramPoint['explicitBounds'], containsAll(<double>[10, 50, 100]));
  expect(histogramAttributes['route'], '/checkout');
  expect(histogramAttributes['protocol'], protocolLabel);
}
