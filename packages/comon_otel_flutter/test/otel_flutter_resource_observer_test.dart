import 'dart:async';

import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_flutter/comon_otel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryMetricExporter metricExporter;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    metricExporter = InMemoryMetricExporter();

    await Otel.shutdown();
    await Otel.init(
      serviceName: 'flutter-test-app',
      metricReaders: <MetricReader>[
        ExportingMetricReader(exporter: metricExporter),
      ],
    );
  });

  tearDown(() async {
    await Otel.shutdown();
  });

  group('all toggles off (AC1)', () {
    test(
      'install exposes no resourceObserver when every toggle is off',
      () {
        final instrumentation = ComonOtelFlutter.install(
          config: const ComonOtelFlutterConfig(
            observeAppLifecycle: false,
            trackNavigatorRoutes: false,
          ),
        );

        expect(instrumentation.resourceObserver, isNull);

        instrumentation.dispose();
      },
    );

    test('disabled signals never subscribe, record, or emit', () async {
      var thermalStreamCalled = false;
      final observer = OtelFlutterResourceObserver(
        storageFreeBytesGetter: () async => 123,
        thermalStateStreamGetter: () {
          thermalStreamCalled = true;
          return const Stream<String>.empty();
        },
      );

      observer.start();
      await observer.recordStorageMilestone('startup');
      await observer.recordBatteryMoment('startup');
      await Otel.forceFlush();

      expect(thermalStreamCalled, isFalse);
      expect(metricExporter.lastMetricNamed('app.device.storage.free'), isNull);
      expect(
        metricExporter.lastMetricNamed('app.device.battery.level'),
        isNull,
      );
      expect(
        metricExporter.lastMetricNamed('app.device.battery.state'),
        isNull,
      );
      expect(metricExporter.lastMetricNamed('app.device.thermal.count'), isNull);
      expect(metricExporter.lastMetricNamed('app.process.memory.rss'), isNull);

      observer.dispose();
    });
  });

  group('battery (AC2)', () {
    test('level metric never carries the numeric level as an attribute', () async {
      final observer = OtelFlutterResourceObserver(
        trackBatteryMetrics: true,
        batteryLevelGetter: () async => 42,
        batteryStateStreamGetter: () => const Stream<String>.empty(),
      );

      observer.start();
      await observer.recordBatteryMoment('startup');
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.battery.level',
      );
      expect(metric, isNotNull);
      final point = metric!.points.single;
      expect(point.value, 42.0);
      expect(point.attributes['moment'], 'startup');
      expect(point.attributes.containsKey('level'), isFalse);
      expect(
        point.attributes.values.any((value) => value == 42 || value == 42.0),
        isFalse,
      );

      observer.dispose();
    });

    test('state gauge exposes only the current state label', () async {
      final controller = StreamController<String>();
      final observer = OtelFlutterResourceObserver(
        trackBatteryMetrics: true,
        batteryLevelGetter: () async => 10,
        batteryStateStreamGetter: () => controller.stream,
      );

      observer.start();
      controller.add('charging');
      await Future<void>.delayed(Duration.zero);
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.battery.state',
      );
      expect(metric, isNotNull);
      final point = metric!.points.single;
      expect(point.value, 1.0);
      expect(point.attributes['state'], 'charging');

      observer.dispose();
      await controller.close();
    });

    test('a throwing level getter does not crash and records no point', () async {
      final observer = OtelFlutterResourceObserver(
        trackBatteryMetrics: true,
        batteryLevelGetter: () async => throw StateError('boom'),
        batteryStateStreamGetter: () => const Stream<String>.empty(),
      );

      observer.start();
      await observer.recordBatteryMoment('startup');
      await Otel.forceFlush();

      expect(
        metricExporter.lastMetricNamed('app.device.battery.level'),
        isNull,
      );

      observer.dispose();
    });

    test(
      'a battery-state stream error does not crash start()/dispose()',
      () async {
        final observer = OtelFlutterResourceObserver(
          trackBatteryMetrics: true,
          batteryLevelGetter: () async => 10,
          batteryStateStreamGetter: () =>
              Stream<String>.error(StateError('battery stream boom')),
        );

        await runZonedGuarded(
          () async {
            observer.start();
            await Future<void>.delayed(Duration.zero);
            await Otel.forceFlush();
            observer.dispose();
          },
          (error, stackTrace) {
            fail('unhandled error escaped the observer: $error');
          },
        );
      },
    );
  });

  group('thermal (AC3)', () {
    test('counts only real transitions, not repeats', () async {
      final controller = StreamController<String>();
      final observer = OtelFlutterResourceObserver(
        trackThermalMetrics: true,
        thermalStateStreamGetter: () => controller.stream,
      );

      observer.start();
      for (final state in <String>[
        'nominal',
        'fair',
        'fair',
        'serious',
        'critical',
      ]) {
        controller.add(state);
        await Future<void>.delayed(Duration.zero);
      }
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.thermal.count',
      );
      expect(metric, isNotNull);
      final statesSeen = metric!.points.map(
        (point) => point.attributes['state'],
      );
      expect(statesSeen, containsAll(<String>['fair', 'serious', 'critical']));
      final totalCount = metric.points.fold<num>(
        0,
        (total, point) => total + (point.value ?? 0),
      );
      expect(totalCount, 4);

      observer.dispose();
      await controller.close();
    });

    test('a stream that never emits leaves the counter empty', () async {
      final observer = OtelFlutterResourceObserver(
        trackThermalMetrics: true,
        thermalStateStreamGetter: () => const Stream<String>.empty(),
      );

      observer.start();
      await Otel.forceFlush();

      expect(metricExporter.lastMetricNamed('app.device.thermal.count'), isNull);

      observer.dispose();
    });

    test('dispose cancels the subscription', () async {
      final controller = StreamController<String>();
      final observer = OtelFlutterResourceObserver(
        trackThermalMetrics: true,
        thermalStateStreamGetter: () => controller.stream,
      );

      observer.start();
      controller.add('nominal');
      await Future<void>.delayed(Duration.zero);
      observer.dispose();

      controller.add('fair');
      await Future<void>.delayed(Duration.zero);
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.thermal.count',
      );
      // 'nominal' is the first observed state and counts once; the
      // post-dispose 'fair' must not add a second count.
      expect(metric, isNotNull);
      final totalCount = metric!.points.fold<num>(
        0,
        (total, point) => total + (point.value ?? 0),
      );
      expect(totalCount, 1);

      await controller.close();
    });

    test(
      'an error mid-stream does not crash and later events still count',
      () async {
        final controller = StreamController<String>();
        final observer = OtelFlutterResourceObserver(
          trackThermalMetrics: true,
          thermalStateStreamGetter: () => controller.stream,
        );

        await runZonedGuarded(
          () async {
            observer.start();
            controller.add('nominal');
            await Future<void>.delayed(Duration.zero);
            controller.addError(StateError('thermal stream boom'));
            await Future<void>.delayed(Duration.zero);
            controller.add('fair');
            await Future<void>.delayed(Duration.zero);
            await Otel.forceFlush();
          },
          (error, stackTrace) {
            fail('unhandled error escaped the observer: $error');
          },
        );

        final metric = metricExporter.lastMetricNamed(
          'app.device.thermal.count',
        );
        expect(metric, isNotNull);
        final totalCount = metric!.points.fold<num>(
          0,
          (total, point) => total + (point.value ?? 0),
        );
        // 'nominal' (first state) + 'fair' (real transition) despite the
        // error in between = 2, the stream error itself must not count.
        expect(totalCount, 2);

        observer.dispose();
        await controller.close();
      },
    );

    test('double start() does not leak/duplicate the subscription', () async {
      final controller = StreamController<String>.broadcast();
      final observer = OtelFlutterResourceObserver(
        trackThermalMetrics: true,
        thermalStateStreamGetter: () => controller.stream,
      );

      observer.start();
      observer.start();
      controller.add('nominal');
      await Future<void>.delayed(Duration.zero);
      observer.dispose();

      controller.add('fair');
      await Future<void>.delayed(Duration.zero);
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.thermal.count',
      );
      expect(metric, isNotNull);
      final totalCount = metric!.points.fold<num>(
        0,
        (total, point) => total + (point.value ?? 0),
      );
      // If start() leaked a duplicate subscription, 'nominal' would count
      // twice (2) instead of once.
      expect(totalCount, 1);

      await controller.close();
    });
  });

  group('storage (AC4)', () {
    test('emits one gauge point per milestone with no path/filename', () async {
      // A single mutable "current reading" lets one observer instance
      // record three different milestones with three different byte values,
      // so the gauge accumulates all of them for one collection cycle.
      var currentBytes = 1000;
      final observer = OtelFlutterResourceObserver(
        trackStorageMetrics: true,
        storageFreeBytesGetter: () async => currentBytes,
      );

      await observer.recordStorageMilestone('before_photo_write');
      currentBytes = 2000;
      await observer.recordStorageMilestone('before_sync');
      currentBytes = 3000;
      await observer.recordStorageMilestone('startup');

      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.storage.free',
      );
      expect(metric, isNotNull);
      expect(metric!.points, hasLength(3));
      final milestonesSeen = metric.points.map(
        (point) => point.attributes['milestone'],
      );
      expect(
        milestonesSeen,
        containsAll(<String>['before_photo_write', 'before_sync', 'startup']),
      );
      for (final point in metric.points) {
        expect(point.attributes.containsKey('path'), isFalse);
        expect(point.attributes.containsKey('filename'), isFalse);
      }

      observer.dispose();
    });

    test('null getter result records no point and does not crash', () async {
      final observer = OtelFlutterResourceObserver(
        trackStorageMetrics: true,
        storageFreeBytesGetter: () async => null,
      );

      await observer.recordStorageMilestone('startup');
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.device.storage.free',
      );
      expect(metric, isNull);

      observer.dispose();
    });

    test('a throwing getter does not crash the observer', () async {
      final observer = OtelFlutterResourceObserver(
        trackStorageMetrics: true,
        storageFreeBytesGetter: () async => throw StateError('boom'),
      );

      await observer.recordStorageMilestone('startup');
      await Otel.forceFlush();

      expect(metricExporter.lastMetricNamed('app.device.storage.free'), isNull);

      observer.dispose();
    });
  });

  group('RSS', () {
    test('records a positive value when enabled', () async {
      final observer = OtelFlutterResourceObserver(trackRssMetrics: true);

      observer.start();
      await Otel.forceFlush();

      final metric = metricExporter.lastMetricNamed(
        'app.process.memory.rss',
      );
      expect(metric, isNotNull);
      expect(metric!.points.single.value, greaterThan(0));

      observer.dispose();
    });
  });

  group('edges', () {
    test('Otel not initialized does not crash', () async {
      await Otel.shutdown();

      final observer = OtelFlutterResourceObserver(
        trackStorageMetrics: true,
        trackBatteryMetrics: true,
        trackThermalMetrics: true,
        trackRssMetrics: true,
        storageFreeBytesGetter: () async => 100,
        thermalStateStreamGetter: () => const Stream<String>.empty(),
      );

      observer.start();
      await observer.recordStorageMilestone('startup');
      await observer.recordBatteryMoment('startup');

      observer.dispose();
    });
  });
}
