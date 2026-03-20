part of '../comon_otel_test.dart';

void definePropagationAndTestingTests() {
  group('propagation and testing', () {
    test('injects and extracts W3C trace context and baggage', () async {
      late Map<String, String> carrier;

      await Otel.instance.tracer.traceAsync(
        'w3c-parent',
        fn: () async {
          final baggage = Baggage.empty()
              .withEntry('tenant.id', 'acme')
              .withEntry('user.id', '42', metadata: 'source=test');

          OtelContext.withBaggage(baggage, () {
            carrier = <String, String>{};
            const CompositePropagator(<TextMapPropagator>[
              W3CTraceContextPropagator(),
              W3CBaggagePropagator(),
            ]).inject(OtelContext.current, carrier);
          });
        },
      );

      expect(carrier['traceparent'], isNotNull);
      expect(carrier['traceparent']!.endsWith('-03'), isTrue);
      expect(carrier['baggage'], contains('tenant.id=acme'));

      final extracted = const CompositePropagator(<TextMapPropagator>[
        W3CTraceContextPropagator(),
        W3CBaggagePropagator(),
      ]).extract(carrier);

      expect(carrier, hasCarrierHeader('traceparent'));
      expect(carrier, hasCarrierHeader('baggage'));
      expect(extracted.spanContext, isNotNull);
      expect(extracted, hasRemoteSpanContext(sampled: true));
      expect(extracted.spanContext!.traceFlags.isRandom, isTrue);
      expect(extracted, hasBaggageEntry('tenant.id', 'acme'));
      expect(extracted, hasBaggageEntry('user.id', '42'));
    });

    test('supports remote parent context from extracted headers', () async {
      final extracted = const W3CTraceContextPropagator()
          .extract(<String, String>{
            'traceparent':
                '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03',
            'tracestate': ' vendor=value , acme@tenant = blue ',
          });

      expect(
        extracted.spanContext?.traceState,
        'vendor=value,acme@tenant=blue',
      );

      final span = Otel.instance.tracer.startSpan(
        'remote-child',
        parentContext: extracted.spanContext,
      );
      await span.end();
      await Otel.forceFlush();

      final exported = exporter.lastSpanNamed('remote-child');
      expect(exported, isNotNull);
      expect(exported!.parentSpanId, '00f067aa0ba902b7');
      expect(
        exported.parentSpanContext?.traceId,
        '4bf92f3577b34da6a3ce929d0e0e4736',
      );
      expect(extracted.spanContext?.traceFlags.isRandom, isTrue);
      expect(exported.traceFlags.isRandom, isTrue);
    });

    test('sets random trace flag on new root spans', () async {
      await Otel.instance.tracer.traceAsync('random-root', fn: () async {});
      await Future<void>.delayed(Duration.zero);

      final span = exporter.lastSpanNamed('random-root');
      expect(span, isNotNull);
      expect(span!.traceFlags.isRandom, isTrue);
    });

    test('rejects invalid W3C traceparent headers', () {
      const propagator = W3CTraceContextPropagator();
      final invalidHeaders = <String>[
        '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
        '00-4bf92f3577b34da6a3ce929d0e0e473z-00f067aa0ba902b7-01',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902bg-01',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-09',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-04',
        'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      ];

      for (final header in invalidHeaders) {
        final extracted = propagator.extract(<String, String>{
          'traceparent': header,
          'tracestate': 'vendor=value',
        });
        expect(extracted.spanContext, isNull, reason: header);
      }
    });

    test('rejects invalid tracestate without dropping valid traceparent', () {
      const propagator = W3CTraceContextPropagator();

      final extracted = propagator.extract(<String, String>{
        'traceparent':
            '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        'tracestate': 'UpperCase=value',
      });

      expect(extracted.spanContext, isNotNull);
      expect(extracted.spanContext?.traceState, isNull);
      expect(extracted, hasRemoteSpanContext(sampled: true));
    });

    test('injects and extracts B3 headers', () async {
      final context = OtelContextSnapshot.remote(
        traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
        spanId: const SpanId('00f067aa0ba902b7'),
        traceFlags: TraceFlags.sampled,
      );
      final carrier = <String, String>{};

      const B3Propagator().inject(context, carrier);

      expect(
        carrier,
        hasCarrierHeader('x-b3-traceid', '4bf92f3577b34da6a3ce929d0e0e4736'),
      );
      expect(carrier, hasCarrierHeader('x-b3-spanid', '00f067aa0ba902b7'));
      expect(carrier, hasCarrierHeader('x-b3-sampled', '1'));

      final extracted = const B3Propagator().extract(carrier);
      expect(extracted.spanContext, isNotNull);
      expect(
        extracted,
        hasRemoteSpanContext(
          traceId: context.traceId,
          spanId: context.spanId,
          sampled: true,
        ),
      );
    });

    test('provides matcher helpers for propagation carriers and snapshots', () {
      final carrier = <String, String>{};
      final snapshot = OtelContextSnapshot.remote(
        traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
        spanId: const SpanId('00f067aa0ba902b7'),
        traceFlags: TraceFlags.sampled,
        traceState: const TraceState('vendor=value'),
      );

      const W3CTraceContextPropagator().inject(snapshot, carrier);

      final extracted =
          const CompositePropagator(<TextMapPropagator>[
            W3CTraceContextPropagator(),
            W3CBaggagePropagator(),
          ]).extract(<String, String>{
            ...carrier,
            'baggage': 'tenant.id=acme,user.id=42',
          });

      expect(carrier, hasCarrierHeader('traceparent'));
      expect(carrier, hasCarrierHeader('tracestate', 'vendor=value'));
      expect(extracted, hasRemoteSpanContext(sampled: true));
      expect(
        extracted.traceIdValue,
        const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
      );
      expect(extracted, hasTraceId('4bf92f3577b34da6a3ce929d0e0e4736'));
      expect(extracted, hasBaggageEntry('tenant.id', 'acme'));
      expect(extracted, hasBaggageEntry('user.id', '42'));
    });

    test('does not inject invalid tracestate members', () {
      final carrier = <String, String>{};
      final snapshot = OtelContextSnapshot.remote(
        traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
        spanId: const SpanId('00f067aa0ba902b7'),
        traceFlags: TraceFlags.sampled,
        traceState: const TraceState('UpperCase=value'),
      );

      const W3CTraceContextPropagator().inject(snapshot, carrier);

      expect(carrier, hasCarrierHeader('traceparent'));
      expect(carrier.containsKey('tracestate'), isFalse);
    });

    test(
      'exposes database integration contracts through public mixin',
      () async {
        final repository = _TestRepository();

        final rows = await repository.tracedDbOperation<List<int>>(
          'SELECT',
          table: 'users',
          statement: 'SELECT * FROM users',
          resultCount: (result) => result.length,
          execute: () async => <int>[1, 2, 3],
        );

        await Otel.forceFlush();

        expect(rows, <int>[1, 2, 3]);
        expect(
          exporter.spans,
          contains(
            allOf(
              hasSpanNamed('sqlite.SELECT'),
              hasAttribute(SemanticAttributes.dbSystem, 'sqlite'),
              hasAttribute(SemanticAttributes.dbName, 'test.db'),
            ),
          ),
        );
        expect(
          metricExporter.metrics,
          contains(hasMetricNamed('db.client.operation.count')),
        );
        expect(
          metricExporter.metrics,
          contains(hasMetricNamed('db.client.result_set.size')),
        );
        expect(
          logExporter.logs,
          contains(hasLogBody('Slow DB query detected')),
        );
      },
    );

    test(
      'exposes logger extension protocol for external logging bridges',
      () async {
        final extension = _TestLogExtension();

        await Otel.instance.tracer.traceAsync(
          'bridge-parent',
          fn: () async {
            extension.handleLog(
              timestamp: DateTime.utc(2026, 1, 1),
              level: 'ERROR',
              message: 'bridge-message',
              loggerName: 'external.logger',
              error: StateError('bridge failed'),
              extra: <String, Object>{'source': 'bridge'},
            );
          },
        );

        await Otel.forceFlush();

        expect(logExporter.logs, hasLength(greaterThanOrEqualTo(1)));
        expect(
          logExporter.logs,
          contains(
            allOf(
              hasLogBody('bridge-message'),
              hasSeverity(SeverityMatcher.error),
              hasAttribute('source', 'bridge'),
            ),
          ),
        );
        final bridgeLog = logExporter.logs.firstWhere(
          (log) => log.body == 'bridge-message',
        );
        expect(bridgeLog.loggerName, 'external.logger');
        expect(
          bridgeLog.attributes[SemanticAttributes.exceptionMessage],
          contains('bridge failed'),
        );
        expect(bridgeLog.spanContext, isNotNull);
      },
    );

    test('provides in-memory setup through test helper', () async {
      await Otel.shutdown();
      final helper = await OtelTestHelper.setup(serviceName: 'helper-test');

      await Otel.instance.tracer.traceAsync(
        'helper-span',
        fn: () async {
          Otel.instance.logger.info('helper-log');
          Otel.instance.meter.createIntCounter('helper.counter').add(1);
        },
      );

      await Otel.forceFlush();

      expect(helper.spanExporter.lastSpanNamed('helper-span'), isNotNull);
      expect(helper.logExporter.logs.single.body, 'helper-log');
      expect(
        helper.metricExporter.lastMetricNamed('helper.counter'),
        isNotNull,
      );

      helper.reset();
      expect(helper.spanExporter.spans, isEmpty);
      expect(helper.logExporter.logs, isEmpty);
      expect(helper.metricExporter.metrics, isEmpty);

      await helper.shutdown();
    });

    test('provides matcher helpers for spans and logs', () async {
      await Otel.instance.tracer.traceAsync(
        'matcher-span',
        fn: () async {
          Otel.instance.logger.info(
            'matcher-log',
            attributes: <String, Object>{
              SemanticAttributes.httpRoute: '/match',
            },
          );
        },
      );

      await Otel.forceFlush();

      expect(
        exporter.spans,
        contains(allOf(hasSpanNamed('matcher-span'), hasStatus(SpanStatus.ok))),
      );
      expect(
        exporter.spans,
        contains(
          hasTraceId(
            exporter.lastSpanNamed('matcher-span')!.spanContext.traceId,
          ),
        ),
      );
      expect(
        logExporter.logs,
        contains(
          allOf(
            hasLogBody('matcher-log'),
            hasSeverity(SeverityMatcher.info),
            hasAttribute(SemanticAttributes.httpRoute, '/match'),
            hasTraceId(
              exporter.lastSpanNamed('matcher-span')!.spanContext.traceId,
            ),
          ),
        ),
      );
    });

    test('provides matcher helpers for metrics', () async {
      final counter = Otel.instance.meter.createIntCounter('matcher.counter');
      counter.add(3, attributes: <String, Object>{'kind': 'metric-test'});
      counter.add(4, attributes: <String, Object>{'kind': 'metric-test'});

      await Otel.forceFlush();

      expect(
        metricExporter.metrics,
        contains(
          allOf(
            hasMetricNamed('matcher.counter'),
            hasMetricType(MetricInstrumentType.counter),
            hasPointValue(7),
            hasPointAttribute('kind', 'metric-test'),
          ),
        ),
      );
    });
  });
}
