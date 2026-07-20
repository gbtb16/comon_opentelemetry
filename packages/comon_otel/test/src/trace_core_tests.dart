part of '../comon_otel_test.dart';

void defineTraceCoreTests() {
  group('trace core', () {
    test('exports a completed synchronous span', () async {
      final link = SpanLink(
        context: SpanContext.local(
          traceId: const TraceId('11111111111111111111111111111111'),
          spanId: const SpanId('2222222222222222'),
          traceFlags: TraceFlags.sampled,
          traceState: const TraceState('vendor=value'),
        ),
        attributes: <String, Object>{'link.kind': 'batch'},
      );

      final value = Otel.instance.tracer.trace(
        'sync-operation',
        attributes: <String, Object>{'answer': 42},
        links: <SpanLink>[link],
        fn: () => 42,
      );

      await Future<void>.delayed(Duration.zero);

      expect(value, 42);
      expect(exporter.spans, hasLength(1));

      final span = exporter.lastSpanNamed('sync-operation');
      expect(span, isNotNull);
      expect(span!.status, SpanStatus.ok);
      expect(span.traceIdValue, span.spanContext.traceIdValue);
      expect(span.spanIdValue, span.spanContext.spanIdValue);
      expect(span.traceFlags, span.spanContext.traceFlags);
      expect(span.attributes['answer'], 42);
      expect(span.links, hasLength(1));
      expect(span.links.single.context.traceId, link.context.traceId);
      expect(span.links.single.attributes['link.kind'], 'batch');
      expect(span.resource.attributes['service.name'], 'test-service');
    });

    test('records links after span creation while preserving order', () async {
      final firstLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('11111111111111111111111111111111'),
          spanId: const SpanId('aaaaaaaaaaaaaaaa'),
          traceFlags: TraceFlags.sampled,
        ),
        attributes: const <String, Object>{'link.order': 1},
      );
      final secondLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('22222222222222222222222222222222'),
          spanId: const SpanId('bbbbbbbbbbbbbbbb'),
          traceFlags: TraceFlags.sampled,
        ),
        attributes: const <String, Object>{'link.order': 2},
      );
      final thirdLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('33333333333333333333333333333333'),
          spanId: const SpanId('cccccccccccccccc'),
          traceFlags: TraceFlags.sampled,
        ),
        attributes: const <String, Object>{'link.order': 3},
      );

      final span = Otel.instance.tracer.startSpan('linked-after-start');
      span.addLink(firstLink);
      span.addLinks(<SpanLink>[secondLink, thirdLink]);

      await span.end();
      await Future<void>.delayed(Duration.zero);

      final exported = exporter.lastSpanNamed('linked-after-start');
      expect(exported, isNotNull);
      expect(exported!.links, hasLength(3));
      expect(exported.links[0].context.traceId, firstLink.context.traceId);
      expect(exported.links[1].context.traceId, secondLink.context.traceId);
      expect(exported.links[2].context.traceId, thirdLink.context.traceId);
      expect(
        exported.links.map((link) => link.attributes['link.order']).toList(),
        <Object?>[1, 2, 3],
      );
    });

    test('exposes typed trace primitives through SpanContext', () {
      const context = SpanContext(
        traceId: '4BF92F3577B34DA6A3CE929D0E0E4736',
        spanId: '00F067AA0BA902B7',
        sampled: true,
        traceState: ' vendor=value ',
      );

      expect(context.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(context.spanId, '00f067aa0ba902b7');
      expect(
        context.traceIdValue,
        const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
      );
      expect(context.spanIdValue, const SpanId('00f067aa0ba902b7'));
      expect(context.traceFlags, TraceFlags.sampled);
      expect(context.traceStateValue, const TraceState(' vendor=value '));
      expect(context.traceStateValue?.normalized, 'vendor=value');
    });

    test('supports typed trace primitive constructors', () {
      final context = SpanContext.remote(
        traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
        spanId: const SpanId('00f067aa0ba902b7'),
        traceFlags: const TraceFlags(0x01),
        traceState: const TraceState('vendor=value'),
      );

      expect(context.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(context.spanId, '00f067aa0ba902b7');
      expect(context.sampled, isTrue);
      expect(context.isRemote, isTrue);
      expect(context.traceState, 'vendor=value');
    });

    test('supports typed local and remote SpanContext factories', () {
      final local = SpanContext.local(
        traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
        spanId: const SpanId('00f067aa0ba902b7'),
        traceFlags: TraceFlags.sampled,
      );
      final remote = SpanContext.remote(
        traceId: const TraceId('11111111111111111111111111111111'),
        spanId: const SpanId('2222222222222222'),
        traceFlags: TraceFlags.none,
        traceState: const TraceState('vendor=value'),
      );

      expect(local.isRemote, isFalse);
      expect(local.sampled, isTrue);
      expect(remote.isRemote, isTrue);
      expect(remote.sampled, isFalse);
      expect(remote.traceStateValue?.normalized, 'vendor=value');
    });

    test('validates trace primitive wrappers', () {
      expect(const TraceId('4bf92f3577b34da6a3ce929d0e0e4736').isValid, isTrue);
      expect(
        const TraceId('00000000000000000000000000000000').isValid,
        isFalse,
      );

      expect(const SpanId('00f067aa0ba902b7').isValid, isTrue);
      expect(const SpanId('0000000000000000').isValid, isFalse);

      expect(const TraceFlags(0x01).isSampled, isTrue);
      expect(const TraceFlags(0x02).isRandom, isTrue);
      expect(const TraceFlags(0x03).isSampled, isTrue);
      expect(const TraceFlags(0x03).isRandom, isTrue);
      expect(TraceFlags.tryParseHex('01'), TraceFlags.sampled);
      expect(TraceFlags.tryParseHex('02'), TraceFlags.random);
      expect(TraceFlags.tryParseHex('03'), TraceFlags.sampledAndRandom);
      expect(TraceFlags.tryParseHex('gg'), isNull);

      expect(const TraceState(' vendor=value ').normalized, 'vendor=value');
      expect(const TraceState('UpperCase=value').isValid, isFalse);
      expect(TraceState.tryParse(' vendor=value ')?.value, 'vendor=value');
      expect(TraceState.tryParse('UpperCase=value'), isNull);
    });

    test('parses structured tracestate members', () {
      const traceState = TraceState(' vendor=value , acme@tenant = blue ');

      expect(traceState.members, <TraceStateMember>[
        const TraceStateMember(key: 'vendor', value: 'value'),
        const TraceStateMember(key: 'acme@tenant', value: 'blue'),
      ]);
      expect(traceState['vendor']?.value, 'value');
      expect(traceState['acme@tenant']?.value, 'blue');
      expect(traceState['missing'], isNull);
    });

    test('builds tracestate from structured members', () {
      final traceState = TraceState.fromMembers(<TraceStateMember>[
        const TraceStateMember(key: 'vendor', value: 'value'),
        const TraceStateMember(key: 'acme@tenant', value: 'blue'),
      ]);

      expect(traceState.value, 'vendor=value,acme@tenant=blue');
      expect(traceState.members, hasLength(2));
      expect(
        TraceState.tryFromMembers(<TraceStateMember>[
          const TraceStateMember(key: 'UpperCase', value: 'value'),
        ]),
        isNull,
      );
    });

    test('lets samplers modify tracestate for new spans', () async {
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'sampler-tracestate-test',
        sampler: SamplerConfig.custom(
          () => const _TraceStateInjectingSampler(TraceState('vendor=sampled')),
        ),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      await Otel.instance.tracer.traceAsync(
        'sampler-tracestate',
        fn: () async {},
      );
      await Future<void>.delayed(Duration.zero);

      final span = exporter.lastSpanNamed('sampler-tracestate');
      expect(span, isNotNull);
      expect(span!.traceStateValue?.normalized, 'vendor=sampled');
    });

    test('parent based sampler preserves parent tracestate', () async {
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'parent-tracestate-test',
        sampler: SamplerConfig.custom(
          () => const ParentBasedSampler(root: AlwaysOffSampler()),
        ),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final child = Otel.instance.tracer.startSpan(
        'parent-tracestate-child',
        parentContext: SpanContext.remote(
          traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
          spanId: const SpanId('00f067aa0ba902b7'),
          traceFlags: TraceFlags.sampled,
          traceState: const TraceState('vendor=parent'),
        ),
      );

      await child.end();
      await Future<void>.delayed(Duration.zero);

      final span = exporter.lastSpanNamed('parent-tracestate-child');
      expect(span, isNotNull);
      expect(span!.sampled, isTrue);
      expect(span.traceStateValue?.normalized, 'vendor=parent');
    });

    test(
      'parent based sampler honors remote sampled delegate override',
      () async {
        await Otel.shutdown();
        await Otel.init(
          serviceName: 'parent-remote-delegate-test',
          sampler: SamplerConfig.custom(
            () => const ParentBasedSampler(
              root: AlwaysOnSampler(),
              remoteParentSampled: AlwaysOffSampler(),
            ),
          ),
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          metricReaders: <MetricReader>[
            ExportingMetricReader(exporter: metricExporter),
          ],
          logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
        );

        final child = Otel.instance.tracer.startSpan(
          'parent-remote-override',
          parentContext: SpanContext.remote(
            traceId: const TraceId('5bf92f3577b34da6a3ce929d0e0e4736'),
            spanId: const SpanId('10f067aa0ba902b7'),
            traceFlags: TraceFlags.sampled,
            traceState: const TraceState('vendor=remote'),
          ),
        );

        await child.end();
        await Future<void>.delayed(Duration.zero);

        expect(child.sampled, isFalse);
        expect(exporter.lastSpanNamed('parent-remote-override'), isNull);
      },
    );

    test(
      'parent based sampler honors local not-sampled delegate override',
      () async {
        await Otel.shutdown();
        await Otel.init(
          serviceName: 'parent-local-delegate-test',
          sampler: SamplerConfig.custom(
            () => const ParentBasedSampler(
              root: AlwaysOffSampler(),
              localParentNotSampled: AlwaysOnSampler(),
            ),
          ),
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          metricReaders: <MetricReader>[
            ExportingMetricReader(exporter: metricExporter),
          ],
          logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
        );

        final child = Otel.instance.tracer.startSpan(
          'parent-local-override',
          parentContext: SpanContext.local(
            traceId: const TraceId('6bf92f3577b34da6a3ce929d0e0e4736'),
            spanId: const SpanId('20f067aa0ba902b7'),
            traceFlags: TraceFlags.none,
            traceState: const TraceState('vendor=local'),
          ),
        );

        await child.end();
        await Future<void>.delayed(Duration.zero);

        final span = exporter.lastSpanNamed('parent-local-override');
        expect(child.sampled, isTrue);
        expect(span, isNotNull);
        expect(span!.traceStateValue?.normalized, 'vendor=local');
      },
    );

    test('passes links into sampler decisions', () async {
      List<SpanLink>? seenLinks;

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'sampler-links-test',
        sampler: SamplerConfig.custom(
          () => _LinkCapturingSampler((links) => seenLinks = links),
        ),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final link = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          spanId: const SpanId('bbbbbbbbbbbbbbbb'),
          traceFlags: TraceFlags.sampled,
        ),
      );

      await Otel.instance.tracer.traceAsync(
        'sampler-links',
        links: <SpanLink>[link],
        fn: () async {},
      );

      expect(seenLinks, hasLength(1));
      expect(seenLinks!.single.context.traceIdValue, link.context.traceIdValue);
      expect(seenLinks!.single.context.spanIdValue, link.context.spanIdValue);
    });

    test('passes full parent context into sampler decisions', () async {
      final seenSnapshots = <OtelContextSnapshot?>[];

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'sampler-parent-context-test',
        sampler: SamplerConfig.custom(
          () => _SnapshotCapturingSampler(seenSnapshots.add),
        ),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final baggage = Baggage.empty().withEntry('tenant.id', 'acme');
      await OtelContext.withBaggage(
        baggage,
        () => Otel.instance.tracer.traceAsync(
          'sampler-baggage-context',
          fn: () async {},
        ),
      );

      final explicitParent = OtelContextSnapshot.remote(
        traceId: const TraceId('12121212121212121212121212121212'),
        spanId: const SpanId('3434343434343434'),
        traceFlags: TraceFlags.sampled,
        traceState: const TraceState('vendor=value'),
        baggage: baggage,
      );
      final span = Otel.instance.tracer.startSpan(
        'sampler-explicit-parent-context',
        parentSnapshot: explicitParent,
      );
      await span.end();
      await Future<void>.delayed(Duration.zero);

      expect(seenSnapshots, hasLength(2));

      final baggageOnlySnapshot = seenSnapshots.first;
      expect(baggageOnlySnapshot, isNotNull);
      expect(baggageOnlySnapshot!.spanContext, isNull);
      expect(baggageOnlySnapshot.baggage.getEntry('tenant.id'), 'acme');

      final parentSnapshot = seenSnapshots.last;
      expect(parentSnapshot, isNotNull);
      expect(parentSnapshot!.traceIdValue, explicitParent.traceIdValue);
      expect(parentSnapshot.spanIdValue, explicitParent.spanIdValue);
      expect(parentSnapshot.baggage.getEntry('tenant.id'), 'acme');
    });

    test('trace id ratio sampler writes threshold tracestate', () async {
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'ratio-threshold-test',
        sampler: SamplerConfig.ratio(0.25),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final span = Otel.instance.tracer.startSpan(
        'ratio-threshold',
        parentContext: SpanContext.remote(
          traceId: const TraceId('00000000aaaaaaaaaaaaaaaaaaaaaaaa'),
          spanId: const SpanId('00f067aa0ba902b7'),
          traceFlags: TraceFlags.none,
        ),
      );

      await span.end();
      await Future<void>.delayed(Duration.zero);

      final exported = exporter.lastSpanNamed('ratio-threshold');
      expect(exported, isNotNull);
      expect(exported!.sampled, isTrue);
      expect(exported.traceStateValue?['ot']?.value, 'th:c');
    });

    test('trace id ratio sampler preserves existing ot subkeys', () async {
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'ratio-threshold-ot-test',
        sampler: SamplerConfig.ratio(1.0),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final span = Otel.instance.tracer.startSpan(
        'ratio-threshold-preserve',
        parentContext: SpanContext.remote(
          traceId: const TraceId('11111111111111111111111111111111'),
          spanId: const SpanId('00f067aa0ba902b7'),
          traceFlags: TraceFlags.none,
          traceState: const TraceState(
            'vendor=value,ot=rv:6e6d1a75832a2f;p:8;th:f',
          ),
        ),
      );

      await span.end();
      await Future<void>.delayed(Duration.zero);

      final exported = exporter.lastSpanNamed('ratio-threshold-preserve');
      expect(exported, isNotNull);
      expect(exported!.traceStateValue?['vendor']?.value, 'value');

      final otMembers = _parseOtelMembers(
        exported.traceStateValue!['ot']!.value,
      );
      expect(otMembers['rv'], '6e6d1a75832a2f');
      expect(otMembers['p'], '8');
      expect(otMembers['th'], '0');
    });

    test('always record keeps record-only spans out of exporters', () async {
      final processor = _RecordingSpanProcessor();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'always-record-test',
        sampler: SamplerConfig.alwaysRecord(root: const AlwaysOffSampler()),
        spanProcessors: <SpanProcessor>[
          processor,
          SimpleSpanProcessor(exporter),
        ],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final span = Otel.instance.tracer.startSpan('always-record-span');
      span.setAttribute('kept', true);

      await span.end();
      await Future<void>.delayed(Duration.zero);

      expect(span.isRecording, isTrue);
      expect(span.sampled, isFalse);
      expect(span.attributes['kept'], isTrue);
      expect(processor.started, hasLength(1));
      expect(processor.ended, hasLength(1));
      expect(processor.started.single.isRecording, isTrue);
      expect(processor.started.single.sampled, isFalse);
      expect(exporter.lastSpanNamed('always-record-span'), isNull);
    });

    test(
      'non-recording spans still get ids and expose instrumentation scope',
      () async {
        final processor = _RecordingSpanProcessor();

        await Otel.shutdown();
        await Otel.init(
          serviceName: 'always-off-test',
          sampler: SamplerConfig.alwaysOff(),
          spanProcessors: <SpanProcessor>[processor],
          metricReaders: <MetricReader>[
            ExportingMetricReader(exporter: metricExporter),
          ],
          logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
        );

        final span = Otel.instance.tracer.startSpan('always-off-span');

        expect(span.isRecording, isFalse);
        expect(span.sampled, isFalse);
        expect(span.instrumentationScope, Otel.instance.tracer.name);
        expect(span.traceId, isNotEmpty);
        expect(span.spanId, isNotEmpty);
        expect(span.traceIdValue.isValid, isTrue);
        expect(span.spanIdValue.isValid, isTrue);

        await span.end();
        await Future<void>.delayed(Duration.zero);

        expect(processor.started, isEmpty);
        expect(processor.ended, hasLength(1));
        expect(
          processor.ended.single.instrumentationScope,
          Otel.instance.tracer.name,
        );
        expect(processor.ended.single.isRecording, isFalse);
        expect(exporter.lastSpanNamed('always-off-span'), isNull);
      },
    );

    test(
      'tracer and meter expose full instrumentation scope metadata',
      () async {
        final tracer = Otel.instance.tracerProvider.getTracer(
          'package.tracer',
          version: '1.2.3',
          schemaUrl: 'https://opentelemetry.io/schemas/1.24.0',
          attributes: const <String, Object>{'library.language': 'dart'},
        );
        final meter = Otel.instance.meterProvider.getMeter(
          'package.meter',
          version: '2.3.4',
          schemaUrl: 'https://opentelemetry.io/schemas/1.25.0',
          attributes: const <String, Object>{'library.type': 'metrics'},
        );

        expect(tracer.name, 'package.tracer');
        expect(tracer.version, '1.2.3');
        expect(tracer.schemaUrl, 'https://opentelemetry.io/schemas/1.24.0');
        expect(tracer.attributes['library.language'], 'dart');
        expect(meter.name, 'package.meter');
        expect(meter.version, '2.3.4');
        expect(meter.schemaUrl, 'https://opentelemetry.io/schemas/1.25.0');
        expect(meter.attributes['library.type'], 'metrics');

        final span = tracer.startSpan('scoped-span');
        await span.end();
        await Future<void>.delayed(Duration.zero);

        final exportedSpan = exporter.lastSpanNamed('scoped-span')!;
        expect(exportedSpan.instrumentationScope, 'package.tracer');
        expect(exportedSpan.scope?.version, '1.2.3');
        expect(
          exportedSpan.scope?.schemaUrl,
          'https://opentelemetry.io/schemas/1.24.0',
        );
        expect(exportedSpan.scope?.attributes['library.language'], 'dart');

        meter.createIntCounter('scoped.counter').add(1);
        await Otel.forceFlush();

        final exportedMetric = metricExporter.lastMetricNamed(
          'scoped.counter',
        )!;
        expect(exportedMetric.instrumentationScope, 'package.meter');
        expect(exportedMetric.scope?.version, '2.3.4');
        expect(
          exportedMetric.scope?.schemaUrl,
          'https://opentelemetry.io/schemas/1.25.0',
        );
        expect(exportedMetric.scope?.attributes['library.type'], 'metrics');
      },
    );

    test('enforces span limits for attributes events and links', () async {
      final firstLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('77777777777777777777777777777777'),
          spanId: const SpanId('aaaaaaaaaaaaaaaa'),
          traceFlags: TraceFlags.sampled,
        ),
        attributes: const <String, Object>{'keep': 1, 'drop': 2},
      );
      final secondLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('88888888888888888888888888888888'),
          spanId: const SpanId('bbbbbbbbbbbbbbbb'),
          traceFlags: TraceFlags.sampled,
        ),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'span-limits-test',
        spanLimits: const SpanLimits(
          attributeCountLimit: 2,
          eventCountLimit: 1,
          linkCountLimit: 1,
          attributePerEventCountLimit: 1,
          attributePerLinkCountLimit: 1,
        ),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final span = Otel.instance.tracer.startSpan(
        'limited-span',
        attributes: const <String, Object>{'a': 1, 'b': 2, 'c': 3},
        links: <SpanLink>[firstLink, secondLink],
      );

      span.setAttribute('b', 20);
      span.setAttribute('d', 4);
      span.addEvent(
        'kept-event',
        attributes: const <String, Object>{'x': 1, 'y': 2},
      );
      span.addEvent('dropped-event');

      await span.end();
      await Future<void>.delayed(Duration.zero);

      final exported = exporter.lastSpanNamed('limited-span');
      expect(exported, isNotNull);
      expect(exported!.attributes, <String, Object>{'a': 1, 'b': 20});
      expect(exported.events, hasLength(1));
      expect(exported.events.single.attributes, <String, Object>{'x': 1});
      expect(exported.links, hasLength(1));
      expect(exported.links.single.attributes, <String, Object>{'keep': 1});
      // +1 vs. the pre-session-id baseline: SessionSpanProcessor.onStart
      // also competes for the tight attribute budget and gets dropped too.
      expect(exported.droppedAttributesCount, 5);
      expect(exported.droppedEventsCount, 1);
      expect(exported.droppedLinksCount, 1);
    });

    test('enforces link limits for links added after span creation', () async {
      final firstLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('99999999999999999999999999999999'),
          spanId: const SpanId('dddddddddddddddd'),
          traceFlags: TraceFlags.sampled,
        ),
        attributes: const <String, Object>{'keep': 1, 'drop': 2},
      );
      final secondLink = SpanLink(
        context: SpanContext.remote(
          traceId: const TraceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          spanId: const SpanId('eeeeeeeeeeeeeeee'),
          traceFlags: TraceFlags.sampled,
        ),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'dynamic-link-limits-test',
        spanLimits: const SpanLimits(
          linkCountLimit: 1,
          attributePerLinkCountLimit: 1,
        ),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final span = Otel.instance.tracer.startSpan('dynamic-link-limits');
      span.addLink(firstLink);
      span.addLink(secondLink);

      await span.end();
      await Future<void>.delayed(Duration.zero);

      final exported = exporter.lastSpanNamed('dynamic-link-limits');
      expect(exported, isNotNull);
      expect(exported!.links, hasLength(1));
      expect(exported.links.single.attributes, <String, Object>{'keep': 1});
      expect(exported.droppedAttributesCount, 1);
      expect(exported.droppedLinksCount, 1);
    });

    test(
      'composite sampler applies rule-based drops and annotating attrs',
      () async {
        await Otel.shutdown();
        await Otel.init(
          serviceName: 'composite-rule-test',
          sampler: SamplerConfig.composite(
            ComposableRuleBased(<ComposableRule>[
              ComposableRule(
                predicate: (request) => request.name.startsWith('health'),
                delegate: const ComposableAlwaysOff(),
              ),
              ComposableRule(
                predicate: (request) => request.name.startsWith('checkout'),
                delegate: ComposableAnnotating(
                  attributes: const <String, Object>{
                    'sampler.rule': 'checkout',
                  },
                  delegate: const ComposableAlwaysOn(),
                ),
              ),
            ]),
          ),
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          metricReaders: <MetricReader>[
            ExportingMetricReader(exporter: metricExporter),
          ],
          logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
        );

        await Otel.instance.tracer.traceAsync('health-check', fn: () async {});
        await Otel.instance.tracer.traceAsync(
          'checkout-submit',
          attributes: const <String, Object>{'input.attr': 'present'},
          fn: () async {},
        );
        await Future<void>.delayed(Duration.zero);

        expect(exporter.lastSpanNamed('health-check'), isNull);

        final exported = exporter.lastSpanNamed('checkout-submit');
        expect(exported, isNotNull);
        expect(exported!.attributes['input.attr'], 'present');
        expect(exported.attributes['sampler.rule'], 'checkout');
        expect(exported.traceStateValue?['ot']?.value, 'th:0');
      },
    );

    test('composite probability sampler uses explicit randomness', () async {
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'composite-probability-test',
        sampler: SamplerConfig.composite(ComposableProbability(0.25)),
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      final span = Otel.instance.tracer.startSpan(
        'composable-probability',
        parentContext: SpanContext.remote(
          traceId: const TraceId('22222222222222222222222222222222'),
          spanId: const SpanId('00f067aa0ba902b7'),
          traceFlags: TraceFlags.none,
          traceState: const TraceState('vendor=value,ot=rv:f0000000000000'),
        ),
      );

      await span.end();
      await Future<void>.delayed(Duration.zero);

      final exported = exporter.lastSpanNamed('composable-probability');
      expect(exported, isNotNull);
      expect(exported!.sampled, isTrue);
      final otMembers = _parseOtelMembers(
        exported.traceStateValue!['ot']!.value,
      );
      expect(otMembers['rv'], 'f0000000000000');
      expect(otMembers['th'], 'c');
    });

    test(
      'composite parent threshold propagates reliable parent threshold',
      () async {
        await Otel.shutdown();
        await Otel.init(
          serviceName: 'composite-parent-threshold-test',
          sampler: SamplerConfig.composite(
            ComposableParentThreshold(root: ComposableProbability(0.25)),
          ),
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          metricReaders: <MetricReader>[
            ExportingMetricReader(exporter: metricExporter),
          ],
          logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
        );

        final span = Otel.instance.tracer.startSpan(
          'composable-parent-threshold',
          parentContext: SpanContext.remote(
            traceId: const TraceId('33333333333333333333333333333333'),
            spanId: const SpanId('00f067aa0ba902b7'),
            traceFlags: TraceFlags.sampled,
            traceState: const TraceState(
              'vendor=value,ot=rv:f0000000000000;th:c',
            ),
          ),
        );

        await span.end();
        await Future<void>.delayed(Duration.zero);

        final exported = exporter.lastSpanNamed('composable-parent-threshold');
        expect(exported, isNotNull);
        expect(exported!.sampled, isTrue);
        final otMembers = _parseOtelMembers(
          exported.traceStateValue!['ot']!.value,
        );
        expect(otMembers['rv'], 'f0000000000000');
        expect(otMembers['th'], 'c');
      },
    );

    test(
      'composite parent threshold keeps sampled parent without threshold',
      () async {
        await Otel.shutdown();
        await Otel.init(
          serviceName: 'composite-parent-without-threshold-test',
          sampler: SamplerConfig.composite(
            ComposableParentThreshold(root: ComposableProbability(0.25)),
          ),
          spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
          metricReaders: <MetricReader>[
            ExportingMetricReader(exporter: metricExporter),
          ],
          logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
        );

        final span = Otel.instance.tracer.startSpan(
          'composable-parent-no-threshold',
          parentContext: SpanContext.remote(
            traceId: const TraceId('44444444444444444444444444444444'),
            spanId: const SpanId('00f067aa0ba902b7'),
            traceFlags: TraceFlags.sampled,
            traceState: const TraceState('vendor=value'),
          ),
        );

        await span.end();
        await Future<void>.delayed(Duration.zero);

        final exported = exporter.lastSpanNamed(
          'composable-parent-no-threshold',
        );
        expect(exported, isNotNull);
        expect(exported!.sampled, isTrue);
        expect(exported.traceStateValue?['vendor']?.value, 'value');
        expect(exported.traceStateValue?['ot'], isNull);
      },
    );

    test('propagates parent span through zone context', () async {
      await Otel.instance.tracer.traceAsync(
        'parent',
        fn: () async {
          await Otel.instance.tracer.traceAsync('child', fn: () async {});
        },
      );

      await Future<void>.delayed(Duration.zero);

      final parent = exporter.lastSpanNamed('parent');
      final child = exporter.lastSpanNamed('child');

      expect(parent, isNotNull);
      expect(child, isNotNull);
      expect(child!.parentSpanIdValue, parent!.spanIdValue);
      expect(child.traceIdValue, parent.traceIdValue);
    });

    test(
      'captures and restores OTel context across isolate boundaries',
      () async {
        late String parentTraceId;

        final result = await Otel.instance.tracer.traceAsync(
          'isolate-parent',
          fn: () async {
            parentTraceId = OtelContext.currentSpan!.spanContext.traceId;
            final baggage = Baggage.empty().withEntry('tenant.id', 'acme');

            return OtelContext.withBaggage(baggage, () {
              return OtelIsolate.run<Map<String, Object?>>((context) async {
                return <String, Object?>{
                  'traceId': context.traceId,
                  'tenant': Baggage.current.getEntry('tenant.id'),
                };
              });
            });
          },
        );

        expect(result['traceId'], parentTraceId);
        expect(result['tenant'], 'acme');
      },
    );

    test('creates a child span when isolate runtime is initialized', () async {
      late String parentTraceId;
      late String parentSpanId;

      final result = await Otel.instance.tracer.traceAsync(
        'outer-parent',
        fn: () async {
          parentTraceId = OtelContext.currentSpan!.spanContext.traceId;
          parentSpanId = OtelContext.currentSpan!.spanContext.spanId;

          return OtelIsolate.run<Map<String, Object?>>(
            (context) async {
              final currentSpan = OtelContext.currentSpan;
              return <String, Object?>{
                'traceId': context.traceId,
                'currentTraceId': currentSpan?.traceId,
                'parentSpanId': currentSpan?.parentSpanId,
                'threadType':
                    currentSpan?.attributes[SemanticAttributes.threadType],
              };
            },
            spanName: 'isolate-child',
            initialize: () async {
              await Otel.init(serviceName: 'isolate-test');
            },
          );
        },
      );

      expect(result['traceId'], parentTraceId);
      expect(result['currentTraceId'], parentTraceId);
      expect(result['parentSpanId'], parentSpanId);
      expect(result['threadType'], 'isolate');
    });

    test('records exceptions and rethrows', () async {
      expect(
        () => Otel.instance.tracer.trace(
          'failing-operation',
          fn: () => throw StateError('boom'),
        ),
        throwsStateError,
      );

      await Future<void>.delayed(Duration.zero);

      final span = exporter.lastSpanNamed('failing-operation');
      expect(span, isNotNull);
      expect(span!.status, SpanStatus.error);
      expect(span.events, hasLength(1));
      expect(span.events.first.name, 'exception');
      expect(
        span.events.first.attributes[SemanticAttributes.exceptionMessage],
        contains('boom'),
      );
    });

    test('supports function extensions for traced execution', () async {
      final result = await (() async => 'ok').traced(
        'extension-operation',
        attributes: <String, Object>{'source': 'extension'},
      );

      await Future<void>.delayed(Duration.zero);

      final span = exporter.lastSpanNamed('extension-operation');
      expect(result, 'ok');
      expect(span, isNotNull);
      expect(span!.attributes['source'], 'extension');
    });
  });
}
