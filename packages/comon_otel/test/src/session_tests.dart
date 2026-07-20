part of '../comon_otel_test.dart';

void defineSessionTests() {
  group('session identity', () {
    setUp(OtelSession.resetForTesting);
    tearDown(OtelSession.resetForTesting);

    test('stamps session.id on every exported span with the same value', () async {
      await Otel.instance.tracer.traceAsync(
        'op-a',
        fn: () async {},
      );
      await Otel.instance.tracer.traceAsync(
        'op-b',
        fn: () async {},
      );
      await Otel.forceFlush();

      final spanA = exporter.lastSpanNamed('op-a')!;
      final spanB = exporter.lastSpanNamed('op-b')!;

      expect(spanA.attributes[SemanticAttributes.sessionId], isNotNull);
      expect(
        spanA.attributes[SemanticAttributes.sessionId],
        spanB.attributes[SemanticAttributes.sessionId],
      );
      expect(spanA.attributes[SemanticAttributes.sessionId], OtelSession.id);
    });

    test('stamps session.id on emitted log records', () async {
      Otel.instance.logger.info('hello');
      await Otel.forceFlush();

      final log = logExporter.lastLogNamed('comon_otel');
      expect(log, isNotNull);
      expect(log!.attributes[SemanticAttributes.sessionId], OtelSession.id);
    });

    test('never attaches session.id to exported metrics', () async {
      final counter = Otel.instance.meter.createIntCounter('session.metric');
      counter.add(1, attributes: <String, Object>{'route': '/x'});
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed('session.metric')!;
      for (final point in metric.points) {
        expect(point.attributes.containsKey(SemanticAttributes.sessionId), isFalse);
      }
    });

    test('re-init in the same process keeps the same session id (warm resume)', () async {
      final firstId = OtelSession.id;

      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
      );

      expect(OtelSession.id, firstId);
    });

    test('resetting session state (simulated fresh process) mints a new id', () async {
      final firstId = OtelSession.id;

      OtelSession.resetForTesting();

      expect(OtelSession.id, isNot(firstId));
    });

    test(
      'init with previousSessionId emits exactly one session.rotation span',
      () async {
        final previousId = 'previous-session-id';

        await Otel.init(
          serviceName: 'test-service',
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          previousSessionId: previousId,
        );
        await Otel.forceFlush();

        final rotationSpans = exporter.spansNamed('session.rotation');
        expect(rotationSpans, hasLength(1));
        expect(
          rotationSpans.single.attributes[SemanticAttributes.sessionId],
          OtelSession.id,
        );
        expect(
          rotationSpans.single.attributes[SemanticAttributes.sessionPreviousId],
          previousId,
        );

        // A further re-init with the same previous id must not emit again.
        await Otel.init(
          serviceName: 'test-service',
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          previousSessionId: previousId,
        );
        await Otel.forceFlush();

        expect(exporter.spansNamed('session.rotation'), hasLength(1));
      },
    );

    test('init without previousSessionId never emits a rotation span', () async {
      await Otel.forceFlush();

      expect(exporter.spansNamed('session.rotation'), isEmpty);
    });
  });
}
