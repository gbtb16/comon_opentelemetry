part of '../comon_otel_test.dart';

void defineBatchProcessorHealthTests() {
  group('batch processor health hooks', () {
    test('queueLength reports queued spans below the cap', () async {
      final batchExporter = InMemorySpanExporter();
      final processor = BatchSpanProcessor(
        exporter: batchExporter,
        maxBatchSize: 1000,
        maxQueueSize: 10,
        scheduleDelay: const Duration(hours: 1),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'batch-health-span-depth',
        spanProcessors: <SpanProcessor>[processor],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      for (var i = 0; i < 3; i++) {
        await Otel.instance.tracer.traceAsync('depth-$i', fn: () async {});
      }

      expect(processor.queueLength, 3);
    });

    test('invokes onDrop and caps the queue when spans overflow', () async {
      var drops = 0;
      final batchExporter = InMemorySpanExporter();
      final processor = BatchSpanProcessor(
        exporter: batchExporter,
        maxBatchSize: 1000,
        maxQueueSize: 2,
        scheduleDelay: const Duration(hours: 1),
        onDrop: () => drops++,
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'batch-health-span-overflow',
        spanProcessors: <SpanProcessor>[processor],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
      );

      for (var i = 0; i < 5; i++) {
        await Otel.instance.tracer.traceAsync('overflow-$i', fn: () async {});
      }

      expect(drops, 3);
      expect(processor.queueLength, 2);
    });

    test('queueLength reports queued logs below the cap', () async {
      final batchExporter = InMemoryLogExporter();
      final processor = BatchLogProcessor(
        exporter: batchExporter,
        maxBatchSize: 1000,
        maxQueueSize: 10,
        scheduleDelay: const Duration(hours: 1),
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'batch-health-log-depth',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[processor],
      );

      for (var i = 0; i < 3; i++) {
        Otel.instance.logger.info('depth-$i');
      }

      expect(processor.queueLength, 3);
    });

    test('invokes onDrop and caps the queue when logs overflow', () async {
      var drops = 0;
      final batchExporter = InMemoryLogExporter();
      final processor = BatchLogProcessor(
        exporter: batchExporter,
        maxBatchSize: 1000,
        maxQueueSize: 2,
        scheduleDelay: const Duration(hours: 1),
        onDrop: () => drops++,
      );

      await Otel.shutdown();
      await Otel.init(
        serviceName: 'batch-health-log-overflow',
        spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
        metricReaders: <MetricReader>[
          ExportingMetricReader(exporter: metricExporter),
        ],
        logProcessors: <LogProcessor>[processor],
      );

      for (var i = 0; i < 5; i++) {
        Otel.instance.logger.info('overflow-$i');
      }

      expect(drops, 3);
      expect(processor.queueLength, 2);
    });
  });
}
