part of '../comon_otel_test.dart';

void defineSignalsPipelineTests() {
  group('signals and pipeline', () {
    test('exports metrics through meter provider', () async {
      final counter = Otel.instance.meter.createIntCounter(
        'request.count',
        unit: '{requests}',
        description: 'Counts requests',
      );
      final latency = Otel.instance.meter.createHistogram(
        'request.duration',
        unit: 'ms',
      );

      counter.add(1, attributes: <String, Object>{'route': '/users'});
      await latency.time(
        () async => Future<void>.delayed(Duration.zero),
        attributes: <String, Object>{'route': '/users'},
      );

      await Otel.forceFlush();

      final requestMetric = metricExporter.lastMetricNamed('request.count');
      final durationMetric = metricExporter.lastMetricNamed('request.duration');

      expect(requestMetric, isNotNull);
      expect(requestMetric!.instrumentType, MetricInstrumentType.counter);
      expect(
        requestMetric.aggregationTemporality,
        AggregationTemporality.cumulative,
      );
      expect(requestMetric.isMonotonic, isTrue);
      expect(requestMetric.points, isNotEmpty);
      expect(requestMetric.points.last.attributes['route'], '/users');
      expect(requestMetric.points.single.value, 1);

      expect(durationMetric, isNotNull);
      expect(durationMetric!.instrumentType, MetricInstrumentType.histogram);
      expect(
        durationMetric.aggregationTemporality,
        AggregationTemporality.cumulative,
      );
      expect(durationMetric.points.single.count, 1);
      expect(durationMetric.points.single.sum, isNonNegative);
    });

    test('correlates emitted logs with active span', () async {
      await Otel.instance.tracer.traceAsync(
        'logged-operation',
        fn: () async {
          Otel.instance.logger.info(
            'hello from logger',
            attributes: <String, Object>{'feature': 'logging'},
          );
        },
      );

      await Otel.forceFlush();

      expect(logExporter.logs, hasLength(1));
      final log = logExporter.logs.single;
      final span = exporter.lastSpanNamed('logged-operation');

      expect(log.body, 'hello from logger');
      expect(log.loggerName, 'comon_otel');
      expect(log.severity, SeverityNumber.info);
      expect(log.attributes['feature'], 'logging');
      expect(log.spanContext, isNotNull);
      expect(log.traceIdValue, span!.traceIdValue);
      expect(log.spanIdValue, span.spanIdValue);
      expect(log.traceFlags, span.traceFlags);
      expect(log.spanContext!.traceId, span.spanContext.traceId);
      expect(log.spanContext!.spanId, span.spanContext.spanId);
    });

    test('captures current span context through LogRecord.current', () async {
      late LogRecord record;

      await Otel.instance.tracer.traceAsync(
        'current-log-record-span',
        fn: () async {
          record = LogRecord.current(
            severity: SeverityNumber.info,
            severityText: 'INFO',
            body: 'captured-current-context',
            resource: Otel.instance.loggerProvider.resource,
            loggerName: 'manual.current',
          );
        },
      );

      final span = exporter.lastSpanNamed('current-log-record-span');
      expect(record.loggerName, 'manual.current');
      expect(record.traceIdValue, span!.traceIdValue);
      expect(record.spanIdValue, span.spanIdValue);
      expect(record.traceFlags, span.traceFlags);
    });

    test('supports typed LogRecord construction', () {
      final record = LogRecord.typed(
        timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5),
        observedTimestamp: DateTime.utc(2024, 1, 2, 3, 4, 6),
        severity: SeverityNumber.warn,
        severityText: 'WARN',
        body: 'typed-log-record',
        resource: Resource(serviceName: 'test-service'),
        traceId: const TraceId('4bf92f3577b34da6a3ce929d0e0e4736'),
        spanId: const SpanId('00f067aa0ba902b7'),
        traceFlags: TraceFlags.sampled,
        traceState: const TraceState('vendor=value'),
        isRemote: true,
        loggerName: 'typed.logger',
      );

      expect(record.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(record.spanId, '00f067aa0ba902b7');
      expect(record.sampled, isTrue);
      expect(record.traceStateValue?.normalized, 'vendor=value');
      expect(record.spanContext?.isRemote, isTrue);
      expect(record.loggerName, 'typed.logger');
    });

    test('forceFlush waits for pending simple span and log exports', () async {
      final delayedSpanExporter = _DelayedSpanExporter();
      final delayedLogExporter = _DelayedLogExporter();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'force-flush-test',
        spanProcessors: <SpanProcessor>[
          SimpleSpanProcessor(delayedSpanExporter),
        ],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(delayedLogExporter)],
      );

      await Otel.instance.tracer.traceAsync(
        'flush-span',
        fn: () async {
          Otel.instance.logger.info('flush-log');
        },
      );

      var flushCompleted = false;
      final flushFuture = Otel.forceFlush().then((_) {
        flushCompleted = true;
      });

      await Future<void>.delayed(Duration.zero);

      expect(delayedSpanExporter.pendingCount, 1);
      expect(delayedLogExporter.pendingCount, 1);
      expect(flushCompleted, isFalse);

      delayedSpanExporter.completeAll();
      delayedLogExporter.completeAll();

      await flushFuture;
      expect(flushCompleted, isTrue);
      expect(delayedSpanExporter.forceFlushCount, 1);
      expect(delayedLogExporter.forceFlushCount, 1);
    });

    test('forceFlush delegates to span metric and log exporters', () async {
      final flushSpanExporter = InMemorySpanExporter();
      final flushMetricExporter = InMemoryMetricExporter();
      final flushLogExporter = InMemoryLogExporter();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'exporter-force-flush-test',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(flushSpanExporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: flushMetricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(flushLogExporter)],
      );

      Otel.instance.meter.createIntCounter('flush.counter').add(1);

      await Otel.instance.tracer.traceAsync(
        'flush-delegate-span',
        fn: () async {
          Otel.instance.logger.info('flush-delegate-log');
        },
      );

      await Otel.forceFlush();

      expect(flushSpanExporter.forceFlushCount, 1);
      expect(flushMetricExporter.forceFlushCount, 1);
      expect(flushLogExporter.forceFlushCount, 1);
    });

    test('batch span processor flushes queued spans', () async {
      final batchExporter = InMemorySpanExporter();
      final processor = BatchSpanProcessor(
        exporter: batchExporter,
        maxBatchSize: 10,
        scheduleDelay: const Duration(minutes: 1),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[processor],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      await Otel.instance.tracer.traceAsync('batched-span', fn: () async {});
      expect(batchExporter.spans, isEmpty);

      await Otel.forceFlush();

      expect(batchExporter.lastSpanNamed('batched-span'), isNotNull);
    });

    test('batch log processor flushes queued logs', () async {
      final batchExporter = InMemoryLogExporter();
      final processor = BatchLogProcessor(
        exporter: batchExporter,
        maxBatchSize: 10,
        scheduleDelay: const Duration(minutes: 1),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[processor],
      );

      Otel.instance.logger.info('batched log');
      expect(batchExporter.logs, isEmpty);

      await Otel.forceFlush();

      expect(batchExporter.logs, hasLength(1));
      expect(batchExporter.logs.single.body, 'batched log');
    });

    test('supports composite span exporters', () async {
      final exporterA = InMemorySpanExporter();
      final exporterB = InMemorySpanExporter();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[
          SimpleSpanProcessor(
            CompositeSpanExporter(<SpanExporter>[exporterA, exporterB]),
          ),
        ],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      await Otel.instance.tracer.traceAsync('composite-span', fn: () async {});
      await Future<void>.delayed(Duration.zero);

      expect(exporterA.lastSpanNamed('composite-span'), isNotNull);
      expect(exporterB.lastSpanNamed('composite-span'), isNotNull);

      final result = await CompositeSpanExporter(<SpanExporter>[
        exporterA,
        _FailingSpanExporter(),
      ]).export(const <SpanData>[]);
      expect(result, ExportResult.failure);
    });

    test('supports composite metric exporters', () async {
      final exporterA = InMemoryMetricExporter();
      final exporterB = InMemoryMetricExporter();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(
            exporter: CompositeMetricExporter(<MetricExporter>[
              exporterA,
              exporterB,
            ]),
          ),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      Otel.instance.meter.createIntCounter('composite.metric').add(1);
      await Otel.forceFlush();

      expect(exporterA.lastMetricNamed('composite.metric'), isNotNull);
      expect(exporterB.lastMetricNamed('composite.metric'), isNotNull);

      final result = await CompositeMetricExporter(<MetricExporter>[
        exporterA,
        _FailingMetricExporter(),
      ]).export(const <MetricData>[]);
      expect(result, ExportResult.failure);
    });

    test('supports composite log exporters', () async {
      final exporterA = InMemoryLogExporter();
      final exporterB = InMemoryLogExporter();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[
          SimpleLogProcessor(
            CompositeLogExporter(<LogExporter>[exporterA, exporterB]),
          ),
        ],
      );

      Otel.instance.logger.info('composite-log');
      await Future<void>.delayed(Duration.zero);

      expect(exporterA.logs.any((log) => log.body == 'composite-log'), isTrue);
      expect(exporterB.logs.any((log) => log.body == 'composite-log'), isTrue);

      final result = await CompositeLogExporter(<LogExporter>[
        exporterA,
        _FailingLogExporter(),
      ]).export(const <LogRecord>[]);
      expect(result, ExportResult.failure);
    });

    test('periodic metric reader can export collected metrics', () async {
      final periodicExporter = InMemoryMetricExporter();

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          PeriodicMetricReader(
            exporter: periodicExporter,
            interval: const Duration(milliseconds: 20),
          ),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      Otel.instance.meter.createIntCounter('periodic.count').add(1);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(periodicExporter.lastMetricNamed('periodic.count'), isNotNull);
    });

    test('batch span processor recovers after a flush export throws', () async {
      final throwingExporter = _ThrowOnceSpanExporter();
      final processor = BatchSpanProcessor(
        exporter: throwingExporter,
        maxBatchSize: 1000,
        scheduleDelay: const Duration(minutes: 1),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[processor],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      await Otel.instance.tracer.traceAsync('first-span', fn: () async {});
      // First flush hits the throwing export; the B1 fix swallows it so the
      // chain stays alive and this flush resolves normally.
      await processor.forceFlush();

      await Otel.instance.tracer.traceAsync('second-span', fn: () async {});
      await processor.forceFlush();

      expect(
        throwingExporter.exported.any((span) => span.name == 'second-span'),
        isTrue,
      );
    });

    test('batch log processor recovers after a flush export throws', () async {
      final throwingExporter = _ThrowOnceLogExporter();
      final processor = BatchLogProcessor(
        exporter: throwingExporter,
        maxBatchSize: 1000,
        scheduleDelay: const Duration(minutes: 1),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'test-service',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[processor],
      );

      Otel.instance.logger.info('first-log');
      // The B1 fix swallows the throwing export, so this flush resolves
      // normally.
      await processor.forceFlush();

      Otel.instance.logger.info('second-log');
      await processor.forceFlush();

      expect(
        throwingExporter.exported.any((log) => log.body == 'second-log'),
        isTrue,
      );
    });

    test('BatchSpanProcessor.forceFlush swallows a throwing exporter teardown', () async {
      final exporter = _ThrowingTeardownSpanExporter();
      final processor = BatchSpanProcessor(exporter: exporter);

      // Must complete normally even though the exporter throws on forceFlush.
      await processor.forceFlush();
      await processor.shutdown();

      expect(exporter.forceFlushCalled, isTrue);
      expect(exporter.shutdownCalled, isTrue);
    });
  });
}

final class _ThrowingTeardownSpanExporter implements SpanExporter {
  bool forceFlushCalled = false;
  bool shutdownCalled = false;

  @override
  Future<ExportResult> export(List<SpanData> data) async => ExportResult.success;

  @override
  Future<void> forceFlush() async {
    forceFlushCalled = true;
    throw StateError('teardown boom');
  }

  @override
  Future<void> shutdown() async {
    shutdownCalled = true;
    throw StateError('shutdown boom');
  }
}
