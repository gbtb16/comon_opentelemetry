part of '../otlp_collector_integration_test.dart';

void defineCollectorOverrideAndRetryIntegrationTests() {
  test(
    'honors per-signal HTTP endpoints, headers, compression, and timeout overrides',
    () async {
      final tracesServer = await _HttpCaptureServer.start();
      final metricsServer = await _HttpCaptureServer.start(
        responseDelay: const Duration(milliseconds: 700),
      );
      final logsServer = await _HttpCaptureServer.start();

      addTearDown(tracesServer.close);
      addTearDown(metricsServer.close);
      addTearDown(logsServer.close);

      final startedAt = DateTime.now();
      await _emitIntegrationScenario(
        exporter: OtelExporter.otlpHttp,
        endpoint: 'http://127.0.0.1:1',
        protocolLabel: 'http-overrides',
        tracesEndpoint: 'http://127.0.0.1:${tracesServer.port}/custom/traces',
        metricsEndpoint:
            'http://127.0.0.1:${metricsServer.port}/custom/metrics',
        logsEndpoint: 'http://127.0.0.1:${logsServer.port}/custom/logs',
        otlpHeaders: <String, String>{'authorization': 'Bearer shared'},
        otlpTracesHeaders: <String, String>{'x-signal': 'traces'},
        otlpMetricsHeaders: <String, String>{'x-signal': 'metrics'},
        otlpLogsHeaders: <String, String>{'x-signal': 'logs'},
        otlpTimeout: const Duration(seconds: 2),
        otlpMetricsTimeout: const Duration(milliseconds: 150),
        otlpCompression: OtlpCompression.none,
        otlpTracesCompression: OtlpCompression.gzip,
        otlpMetricsCompression: OtlpCompression.gzip,
        otlpLogsCompression: OtlpCompression.none,
        otlpRetry: const OtlpRetryConfig(maxAttempts: 1),
      );
      final elapsed = DateTime.now().difference(startedAt);

      await _waitForRequestCount(tracesServer, 1);
      await _waitForRequestCount(metricsServer, 1);
      await _waitForRequestCount(logsServer, 1);

      expect(tracesServer.requests, isNotEmpty);
      expect(metricsServer.requests, isNotEmpty);
      expect(logsServer.requests, isNotEmpty);

      expect(
        tracesServer.requests.every(
          (request) => request.path == '/custom/traces',
        ),
        isTrue,
      );
      expect(
        metricsServer.requests.every(
          (request) => request.path == '/custom/metrics',
        ),
        isTrue,
      );
      expect(
        logsServer.requests.every((request) => request.path == '/custom/logs'),
        isTrue,
      );

      final traceRequest = tracesServer.requests.first;
      final metricRequest = metricsServer.requests.first;
      final logRequest = logsServer.requests.first;

      expect(traceRequest.headers['authorization'], 'Bearer shared');
      expect(metricRequest.headers['authorization'], 'Bearer shared');
      expect(logRequest.headers['authorization'], 'Bearer shared');
      expect(traceRequest.headers['x-signal'], 'traces');
      expect(metricRequest.headers['x-signal'], 'metrics');
      expect(logRequest.headers['x-signal'], 'logs');

      expect(traceRequest.headers['content-encoding'], 'gzip');
      expect(metricRequest.headers['content-encoding'], 'gzip');
      expect(logRequest.headers.containsKey('content-encoding'), isFalse);

      expect(_maybeGunzip(traceRequest).first, 0x0a);
      expect(_maybeGunzip(metricRequest).first, 0x0a);
      expect(_maybeGunzip(logRequest).first, 0x0a);

      expect(elapsed, lessThan(const Duration(seconds: 2)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'recovers with OTLP HTTP/protobuf retry when the collector starts late',
    () async {
      final httpPort = await _CollectorHarness._allocatePort();
      final grpcPort = await _CollectorHarness._allocatePort();
      final healthPort = await _CollectorHarness._allocatePort();

      final harnessFuture = Future<_CollectorHarness>.delayed(
        const Duration(milliseconds: 700),
        () => _CollectorHarness.startWithPorts(
          httpPort: httpPort,
          grpcPort: grpcPort,
          healthPort: healthPort,
        ),
      );

      final retry = const OtlpRetryConfig(
        maxAttempts: 6,
        initialDelay: Duration(milliseconds: 200),
        backoffMultiplier: 1.5,
        maxDelay: Duration(milliseconds: 500),
      );

      await _emitIntegrationScenario(
        exporter: OtelExporter.otlpHttp,
        endpoint: 'http://127.0.0.1:$httpPort',
        protocolLabel: 'http-retry-recovery',
        otlpRetry: retry,
      );

      final harness = await harnessFuture;
      addTearDown(harness.dispose);

      _assertRoundTrip(
        'http-retry-recovery',
        traceBatches: await harness.waitForSignal('traces.json'),
        metricBatches: await harness.waitForSignal('metrics.json'),
        logBatches: await harness.waitForSignal('logs.json'),
      );
    },
    skip: _dockerRequirement,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'recovers with OTLP gRPC retry when the collector starts late',
    () async {
      final httpPort = await _CollectorHarness._allocatePort();
      final grpcPort = await _CollectorHarness._allocatePort();
      final healthPort = await _CollectorHarness._allocatePort();

      final harnessFuture = Future<_CollectorHarness>.delayed(
        const Duration(milliseconds: 700),
        () => _CollectorHarness.startWithPorts(
          httpPort: httpPort,
          grpcPort: grpcPort,
          healthPort: healthPort,
        ),
      );

      final retry = const OtlpRetryConfig(
        maxAttempts: 6,
        initialDelay: Duration(milliseconds: 200),
        backoffMultiplier: 1.5,
        maxDelay: Duration(milliseconds: 500),
      );

      await _emitIntegrationScenario(
        exporter: OtelExporter.otlpGrpc,
        endpoint: 'http://127.0.0.1:$grpcPort',
        protocolLabel: 'grpc-retry-recovery',
        otlpRetry: retry,
      );

      final harness = await harnessFuture;
      addTearDown(harness.dispose);

      _assertRoundTrip(
        'grpc-retry-recovery',
        traceBatches: await harness.waitForSignal('traces.json'),
        metricBatches: await harness.waitForSignal('metrics.json'),
        logBatches: await harness.waitForSignal('logs.json'),
      );
    },
    skip: _dockerRequirement,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
