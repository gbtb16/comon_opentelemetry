import 'dart:convert';
import 'dart:io';

import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_demo_backend/demo_backend.dart';
import 'package:test/test.dart';

void main() {
  late InMemorySpanExporter spanExporter;
  DemoBackendServer? server;

  setUp(() async {
    spanExporter = InMemorySpanExporter();
    await Otel.shutdown();
    await Otel.init(
      serviceName: 'demo-integration-test',
      spanProcessors: <SpanProcessor>[SimpleSpanProcessor(spanExporter)],
      metricReaders: const <MetricReader>[],
      logProcessors: const <LogProcessor>[],
    );
    server = await DemoBackendServer.bind(port: 0);
  });

  tearDown(() async {
    await server?.close();
    await Otel.shutdown();
  });

  test(
    'propagates trace context from frontend request to backend span',
    () async {
      final client = HttpClient();

      final response = await Otel.instance.tracer.traceAsync(
        'frontend.submit_order_request',
        kind: SpanKind.client,
        attributes: <String, Object>{
          SemanticAttributes.httpMethod: 'POST',
          SemanticAttributes.httpRoute: '/submit-order',
          SemanticAttributes.httpUrl: '${server!.baseUri}/submit-order',
        },
        fn: () async {
          final carrier = <String, String>{};
          Otel.propagator.inject(OtelContext.current, carrier);

          final request = await client.postUrl(
            server!.baseUri.resolve('/submit-order'),
          );
          carrier.forEach(request.headers.set);
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(<String, Object>{'note': 'hello'}));

          final response = await request.close();
          final body = await utf8.decoder.bind(response).join();
          return (response.statusCode, body);
        },
      );

      await Otel.forceFlush();
      client.close(force: true);
      await _waitForExportedSpans(
        spanExporter,
        names: const <String>{
          'frontend.submit_order_request',
          'backend.submit_order',
        },
      );

      expect(response.$1, HttpStatus.ok);
      expect(response.$2, contains('ok'));

      final frontendSpan = spanExporter.spans.singleWhere(
        (span) => span.name == 'frontend.submit_order_request',
      );
      final backendSpan = spanExporter.spans.singleWhere(
        (span) => span.name == 'backend.submit_order',
      );

      expect(frontendSpan.traceId, backendSpan.traceId);
      expect(backendSpan.parentSpanId, frontendSpan.spanId);
      expect(backendSpan.attributes['frontend.trace_id'], frontendSpan.traceId);
    },
  );
}

Future<void> _waitForExportedSpans(
  InMemorySpanExporter exporter, {
  required Set<String> names,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final exportedNames = exporter.spans.map((span) => span.name).toSet();
    if (exportedNames.containsAll(names)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for exported spans: $names');
}
