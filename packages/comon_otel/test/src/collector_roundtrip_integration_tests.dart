part of '../otlp_collector_integration_test.dart';

void defineCollectorRoundTripIntegrationTests() {
  test(
    'round-trips traces, metrics, and logs through OTLP HTTP/protobuf',
    () async {
      final harness = await _CollectorHarness.start();
      addTearDown(harness.dispose);

      await _emitIntegrationScenario(
        exporter: OtelExporter.otlpHttp,
        endpoint: 'http://127.0.0.1:${harness.httpPort}',
        protocolLabel: 'http-protobuf',
        resourceSchemaUrl: 'https://opentelemetry.io/schemas/1.31.0',
        traceScopeSchemaUrl: 'https://opentelemetry.io/schemas/trace-1.31.0',
        metricScopeSchemaUrl: 'https://opentelemetry.io/schemas/metric-1.31.0',
      );

      _assertRoundTrip(
        'http-protobuf',
        traceBatches: await harness.waitForSignal('traces.json'),
        metricBatches: await harness.waitForSignal('metrics.json'),
        logBatches: await harness.waitForSignal('logs.json'),
        expectedResourceSchemaUrl: 'https://opentelemetry.io/schemas/1.31.0',
        expectedTraceScopeSchemaUrl:
            'https://opentelemetry.io/schemas/trace-1.31.0',
        expectedMetricScopeSchemaUrl:
            'https://opentelemetry.io/schemas/metric-1.31.0',
      );
    },
    skip: _dockerRequirement,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'round-trips traces, metrics, and logs through OTLP gRPC',
    () async {
      final harness = await _CollectorHarness.start();
      addTearDown(harness.dispose);

      await _emitIntegrationScenario(
        exporter: OtelExporter.otlpGrpc,
        endpoint: 'http://127.0.0.1:${harness.grpcPort}',
        protocolLabel: 'grpc',
        resourceSchemaUrl: 'https://opentelemetry.io/schemas/1.31.0',
        traceScopeSchemaUrl: 'https://opentelemetry.io/schemas/trace-1.31.0',
        metricScopeSchemaUrl: 'https://opentelemetry.io/schemas/metric-1.31.0',
      );

      _assertRoundTrip(
        'grpc',
        traceBatches: await harness.waitForSignal('traces.json'),
        metricBatches: await harness.waitForSignal('metrics.json'),
        logBatches: await harness.waitForSignal('logs.json'),
        expectedResourceSchemaUrl: 'https://opentelemetry.io/schemas/1.31.0',
        expectedTraceScopeSchemaUrl:
            'https://opentelemetry.io/schemas/trace-1.31.0',
        expectedMetricScopeSchemaUrl:
            'https://opentelemetry.io/schemas/metric-1.31.0',
      );
    },
    skip: _dockerRequirement,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
