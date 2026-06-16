import 'dart:ui';

import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_flutter/comon_otel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CountingSpanExporter implements SpanExporter {
  int forceFlushCount = 0;
  final List<SpanData> spans = <SpanData>[];

  @override
  Future<ExportResult> export(List<SpanData> data) async {
    spans.addAll(data);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}

void main() {
  late InMemorySpanExporter spanExporter;
  late InMemoryMetricExporter metricExporter;
  late InMemoryLogExporter logExporter;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    spanExporter = InMemorySpanExporter();
    metricExporter = InMemoryMetricExporter();
    logExporter = InMemoryLogExporter();

    await Otel.shutdown();
    await Otel.init(
      serviceName: 'flutter-test-app',
      spanProcessors: <SpanProcessor>[SimpleSpanProcessor(spanExporter)],
      metricReaders: <MetricReader>[
        ExportingMetricReader(exporter: metricExporter),
      ],
      logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
    );
  });

  tearDown(() async {
    await Otel.shutdown();
    FlutterError.onError = FlutterError.presentError;
    PlatformDispatcher.instance.onError = null;
    OtelFlutterErrorHooks.clear();
    OtelFlutterBreadcrumbs.clear();
    OtelFlutterRouteContext.clear();
  });

  test('mobileResourceAttributesFrom builds OTel resource attributes', () {
    final attributes = mobileResourceAttributesFrom(
      osName: 'iOS',
      osVersion: '17.4',
      deviceModelIdentifier: 'iPhone15,2',
      deviceManufacturer: 'Apple',
      serviceVersion: '2.0.1',
    );

    expect(attributes['os.name'], 'iOS');
    expect(attributes['os.version'], '17.4');
    expect(attributes['device.model.identifier'], 'iPhone15,2');
    expect(attributes['device.manufacturer'], 'Apple');
    expect(attributes['service.version'], '2.0.1');
    expect(attributes.containsKey('host.name'), isFalse);
  });

  test('install exposes the navigator observer by default', () {
    final instrumentation = ComonOtelFlutter.install(
      config: const ComonOtelFlutterConfig(observeAppLifecycle: false),
    );

    expect(instrumentation.navigatorObserver, isNotNull);
    expect(instrumentation.frameTimingObserver, isNotNull);
    expect(instrumentation.uiStallObserver, isNotNull);
    expect(instrumentation.startupTracker, isNotNull);

    instrumentation.dispose();
  });

  testWidgets('install records startup span through first frame', (
    tester,
  ) async {
    final instrumentation = ComonOtelFlutter.install(
      config: ComonOtelFlutterConfig(
        observeAppLifecycle: false,
        trackNavigatorRoutes: false,
        appStartupStartTime: DateTime.now().toUtc().subtract(
          const Duration(milliseconds: 25),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('startup'))),
    );
    await tester.pump();
    await Otel.forceFlush();

    final startupSpan = spanExporter.spans.singleWhere(
      (span) => span.name == 'app.startup',
    );
    expect(startupSpan.endTime, isNotNull);
    expect(
      startupSpan.events.map((event) => event.name),
      contains('flutter.first_frame'),
    );
    expect(startupSpan.attributes['flutter.startup.completed'], true);

    instrumentation.dispose();
  });

  test('instrumentation records a first interaction marker once', () async {
    final instrumentation = ComonOtelFlutter.install(
      config: const ComonOtelFlutterConfig(observeAppLifecycle: false),
    );

    instrumentation.markFirstInteraction(
      attributes: const <String, Object>{'flutter.interaction.type': 'tap'},
    );
    instrumentation.markFirstInteraction(
      attributes: const <String, Object>{'flutter.interaction.type': 'tap'},
    );
    await Otel.forceFlush();

    final firstInteractionLogs = logExporter.logs.where(
      (log) => log.body == 'app.first_interaction',
    );
    expect(firstInteractionLogs, hasLength(1));
    expect(
      firstInteractionLogs.single.attributes['flutter.interaction.type'],
      'tap',
    );

    instrumentation.dispose();
  });

  test('binding observer logs lifecycle transitions', () async {
    final observer = OtelFlutterBindingObserver();

    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Otel.forceFlush();

    final log = logExporter.logs.single;
    expect(log.body, 'app.lifecycle');
    expect(log.attributes['flutter.lifecycle.state'], 'resumed');
    expect(log.attributes[SemanticAttributes.appLifecycleState], 'resumed');
  });

  test('flushes telemetry when the app is backgrounded', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final exporter = _CountingSpanExporter();
    await Otel.shutdown();
    await Otel.init(
      serviceName: 'lifecycle-test',
      spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
      metricReaders: const <MetricReader>[],
      logProcessors: const <LogProcessor>[],
    );

    final observer = OtelFlutterBindingObserver();
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);

    // Let the unawaited forceFlush microtask run.
    await Future<void>.delayed(Duration.zero);

    expect(exporter.forceFlushCount, greaterThanOrEqualTo(1));

    await Otel.shutdown();
  });

  test('breadcrumbs keep only the configured tail', () {
    OtelFlutterBreadcrumbs.configure(enabled: true, capacity: 2);

    OtelFlutterBreadcrumbs.add(category: 'test', message: 'first');
    OtelFlutterBreadcrumbs.add(category: 'test', message: 'second');
    OtelFlutterBreadcrumbs.add(category: 'test', message: 'third');

    final trail = OtelFlutterBreadcrumbs.serialize();
    expect(trail, isNotNull);
    expect(trail, isNot(contains('first')));
    expect(trail, contains('second'));
    expect(trail, contains('third'));

    OtelFlutterBreadcrumbs.configure(enabled: true, capacity: 20);
  });

  test(
    'external coexistence hooks receive breadcrumbs and errors with fallback preserved',
    () async {
      final receivedBreadcrumbs = <OtelFlutterBreadcrumbEntry>[];
      final receivedFrameworkErrors = <OtelFlutterErrorSnapshot>[];
      final receivedPlatformErrors = <OtelFlutterErrorSnapshot>[];
      var frameworkFallbackCalls = 0;
      var platformFallbackCalls = 0;

      OtelFlutterErrorHooks.configure(
        breadcrumbListener: receivedBreadcrumbs.add,
        frameworkErrorListener: receivedFrameworkErrors.add,
        platformErrorListener: receivedPlatformErrors.add,
      );

      OtelFlutterBreadcrumbs.add(
        category: 'manual',
        message: 'before_error',
        attributes: const <String, Object>{'step': 1},
      );

      recordFlutterFrameworkError(
        FlutterErrorDetails(
          exception: StateError('coexist framework boom'),
          stack: StackTrace.current,
          context: ErrorDescription('during coexist framework test'),
        ),
        fallback: (_) {
          frameworkFallbackCalls += 1;
        },
      );
      final platformHandled = recordFlutterPlatformError(
        ArgumentError('coexist platform boom'),
        StackTrace.current,
        fallback: (error, stackTrace) {
          platformFallbackCalls += 1;
          return false;
        },
      );

      await Otel.forceFlush();

      expect(receivedBreadcrumbs, isNotEmpty);
      expect(receivedBreadcrumbs.last.message, 'before_error');
      expect(receivedFrameworkErrors, hasLength(1));
      expect(receivedFrameworkErrors.single.source, 'framework');
      expect(
        receivedFrameworkErrors.single.attributes[SemanticAttributes
            .exceptionMessage],
        contains('coexist framework boom'),
      );
      expect(receivedFrameworkErrors.single.breadcrumbs, isNotEmpty);
      expect(receivedPlatformErrors, hasLength(1));
      expect(receivedPlatformErrors.single.source, 'platform_dispatcher');
      expect(
        receivedPlatformErrors.single.attributes[SemanticAttributes
            .exceptionMessage],
        contains('coexist platform boom'),
      );
      expect(frameworkFallbackCalls, 1);
      expect(platformFallbackCalls, 1);
      expect(platformHandled, isTrue);
    },
  );

  test(
    'binding observer records foreground and background duration metrics',
    () async {
      final timeline = <DateTime>[
        DateTime.utc(2026, 3, 20, 10, 0, 0, 0),
        DateTime.utc(2026, 3, 20, 10, 0, 1, 500),
        DateTime.utc(2026, 3, 20, 10, 0, 3, 0),
      ];
      var index = 0;
      final observer = OtelFlutterBindingObserver(now: () => timeline[index++]);

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Otel.forceFlush();

      final foregroundMetric = metricExporter.lastMetricNamed(
        'app.foreground.duration',
      );
      final backgroundMetric = metricExporter.lastMetricNamed(
        'app.background.duration',
      );

      expect(foregroundMetric, isNotNull);
      expect(backgroundMetric, isNotNull);

      final foregroundPoint = foregroundMetric!.points.single;
      final backgroundPoint = backgroundMetric!.points.single;
      expect(foregroundPoint.count, 1);
      expect(foregroundPoint.sum, closeTo(1500, 0.001));
      expect(foregroundPoint.attributes['app.lifecycle.from'], 'resumed');
      expect(foregroundPoint.attributes['app.lifecycle.to'], 'paused');
      expect(backgroundPoint.count, 1);
      expect(backgroundPoint.sum, closeTo(1500, 0.001));
      expect(backgroundPoint.attributes['app.lifecycle.from'], 'paused');
      expect(backgroundPoint.attributes['app.lifecycle.to'], 'resumed');
    },
  );

  test('binding observer records memory pressure log and counter', () async {
    final observer = OtelFlutterBindingObserver();

    observer.didHaveMemoryPressure();
    await Otel.forceFlush();

    final memoryPressureMetric = metricExporter.lastMetricNamed(
      'app.memory_pressure.count',
    );

    expect(memoryPressureMetric, isNotNull);
    expect(memoryPressureMetric!.instrumentType, MetricInstrumentType.counter);
    expect(memoryPressureMetric.points.single.value, 1);
    expect(logExporter.logs.last.body, 'app.memory_pressure');
  });

  testWidgets('navigation emits only a sanitized screen_ready span', (
    tester,
  ) async {
    final observer = OtelNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        routes: <String, WidgetBuilder>{
          '/order/12345': (_) => const Scaffold(body: Text('order')),
        },
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/order/12345'),
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump(); // fires the post-frame callback that ends screen_ready
    await tester.pump();
    await Otel.forceFlush();

    final names = spanExporter.spans.map((span) => span.name).toList();
    expect(names, contains('flutter.screen_ready /order/:id'));
    expect(
      names.any((name) => name.startsWith('flutter.route ')),
      isFalse,
      reason: 'umbrella route span must no longer be created',
    );
    expect(
      names.any((name) => name.contains('12345')),
      isFalse,
      reason: 'route names must be sanitized against cardinality',
    );

    observer.dispose();
  });

  testWidgets('navigator observer records screen-ready spans', (tester) async {
    final observer = OtelNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        routes: <String, WidgetBuilder>{
          '/details': (_) => const Scaffold(body: Text('details')),
        },
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/details'),
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    await Otel.forceFlush();

    final readySpan = spanExporter.spans.singleWhere(
      (span) => span.name == 'flutter.screen_ready /details',
    );
    expect(readySpan.attributes['flutter.route.ready'], true);
    expect(
      readySpan.events.map((event) => event.name),
      contains('flutter.screen_ready'),
    );
    expect(readySpan.attributes[SemanticAttributes.flutterRoute], '/details');
    expect(readySpan.attributes['screen.name'], '/details');
    expect(readySpan.attributes['screen.class'], isNotNull);
    expect(readySpan.attributes['flutter.navigation.action'], 'push');
  });

  test(
    'frame timing observer records frame histograms and slow/jank counters',
    () async {
      final observer = OtelFlutterFrameTimingObserver(
        slowFrameThreshold: const Duration(milliseconds: 16),
        jankFrameThreshold: const Duration(milliseconds: 32),
      );

      observer.recordFrameSample(
        totalSpan: const Duration(milliseconds: 12),
        buildDuration: const Duration(milliseconds: 4),
        rasterDuration: const Duration(milliseconds: 5),
      );
      observer.recordFrameSample(
        totalSpan: const Duration(milliseconds: 20),
        buildDuration: const Duration(milliseconds: 8),
        rasterDuration: const Duration(milliseconds: 9),
      );
      observer.recordFrameSample(
        totalSpan: const Duration(milliseconds: 40),
        buildDuration: const Duration(milliseconds: 15),
        rasterDuration: const Duration(milliseconds: 18),
      );
      await Otel.forceFlush();

      final frameDurationMetric = metricExporter.lastMetricNamed(
        'flutter.frame.duration',
      );
      final buildDurationMetric = metricExporter.lastMetricNamed(
        'flutter.build.duration',
      );
      final rasterDurationMetric = metricExporter.lastMetricNamed(
        'flutter.raster.duration',
      );
      final slowFrameMetric = metricExporter.lastMetricNamed(
        'flutter.frame.slow.count',
      );
      final jankFrameMetric = metricExporter.lastMetricNamed(
        'flutter.frame.jank.count',
      );

      expect(frameDurationMetric, isNotNull);
      expect(
        frameDurationMetric!.instrumentType,
        MetricInstrumentType.histogram,
      );
      expect(frameDurationMetric.points.single.count, 3);
      expect(frameDurationMetric.points.single.sum, closeTo(72, 0.001));

      expect(buildDurationMetric, isNotNull);
      expect(buildDurationMetric!.points.single.count, 3);
      expect(buildDurationMetric.points.single.sum, closeTo(27, 0.001));

      expect(rasterDurationMetric, isNotNull);
      expect(rasterDurationMetric!.points.single.count, 3);
      expect(rasterDurationMetric.points.single.sum, closeTo(32, 0.001));

      expect(slowFrameMetric, isNotNull);
      expect(slowFrameMetric!.instrumentType, MetricInstrumentType.counter);
      expect(slowFrameMetric.points.single.value, 1);
      expect(
        slowFrameMetric
            .points
            .single
            .attributes['flutter.frame.classification'],
        'slow',
      );

      expect(jankFrameMetric, isNotNull);
      expect(jankFrameMetric!.instrumentType, MetricInstrumentType.counter);
      expect(jankFrameMetric.points.single.value, 1);
      expect(
        jankFrameMetric
            .points
            .single
            .attributes['flutter.frame.classification'],
        'jank',
      );
    },
  );

  test(
    'ui stall observer records stall metric, counter, and warning log',
    () async {
      final observer = OtelFlutterUiStallObserver(
        checkInterval: const Duration(milliseconds: 50),
        threshold: const Duration(milliseconds: 100),
      );
      final startedAt = DateTime.utc(2026, 3, 20, 12, 0, 0);

      observer.recordTick(startedAt);
      observer.recordTick(startedAt.add(const Duration(milliseconds: 50)));
      observer.recordTick(startedAt.add(const Duration(milliseconds: 250)));
      await Otel.forceFlush();

      final durationMetric = metricExporter.lastMetricNamed(
        'flutter.ui.stall.duration',
      );
      final countMetric = metricExporter.lastMetricNamed(
        'flutter.ui.stall.count',
      );
      final stallLog = logExporter.logs.singleWhere(
        (log) => log.body == 'flutter.ui_stall',
      );

      expect(durationMetric, isNotNull);
      expect(durationMetric!.instrumentType, MetricInstrumentType.histogram);
      expect(durationMetric.points.single.count, 1);
      expect(durationMetric.points.single.sum, closeTo(150, 0.001));

      expect(countMetric, isNotNull);
      expect(countMetric!.instrumentType, MetricInstrumentType.counter);
      expect(countMetric.points.single.value, 1);
      expect(stallLog.attributes['flutter.ui_stall.delay_ms'], 150.0);
    },
  );

  test('flutter framework errors are recorded as telemetry', () async {
    final instrumentation = ComonOtelFlutter.install(
      config: const ComonOtelFlutterConfig(observeAppLifecycle: false),
    );

    FlutterError.onError?.call(
      FlutterErrorDetails(
        exception: StateError('framework boom'),
        stack: StackTrace.current,
        context: ErrorDescription('during widget build'),
      ),
    );
    await Otel.forceFlush();

    final errorSpan = spanExporter.spans.singleWhere(
      (span) => span.name == 'flutter.error',
    );
    final errorLog = logExporter.logs.singleWhere(
      (log) => log.body == 'flutter.framework_error',
    );

    expect(errorSpan.status, SpanStatus.error);
    expect(
      errorLog.attributes[SemanticAttributes.exceptionMessage],
      contains('framework boom'),
    );

    instrumentation.dispose();
  });

  testWidgets('framework errors include breadcrumb trail from recent signals', (
    tester,
  ) async {
    final lifecycleObserver = OtelFlutterBindingObserver();
    final navigatorObserver = OtelNavigatorObserver();
    final stallObserver = OtelFlutterUiStallObserver(
      checkInterval: const Duration(milliseconds: 50),
      threshold: const Duration(milliseconds: 100),
    );
    final startedAt = DateTime.utc(2026, 3, 20, 15, 0, 0);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[navigatorObserver],
        routes: <String, WidgetBuilder>{
          '/details': (_) => const Scaffold(body: Text('details')),
        },
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/details'),
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    stallObserver.recordTick(startedAt);
    stallObserver.recordTick(startedAt.add(const Duration(milliseconds: 250)));

    recordFlutterFrameworkError(
      FlutterErrorDetails(
        exception: StateError('breadcrumb boom'),
        stack: StackTrace.current,
        context: ErrorDescription('during breadcrumb capture'),
      ),
      fallback: (_) {},
    );
    await Otel.forceFlush();

    final errorLog = logExporter.logs.singleWhere(
      (log) => log.body == 'flutter.framework_error',
    );
    final breadcrumbs =
        errorLog.attributes['flutter.error.breadcrumbs'] as String;

    expect(breadcrumbs, contains('lifecycle resumed'));
    expect(breadcrumbs, contains('navigation push'));
    expect(breadcrumbs, contains('performance ui_stall'));
    expect(breadcrumbs, contains('/details'));

    navigatorObserver.dispose();
    stallObserver.dispose();
  });

  testWidgets(
    'framework errors include grouping, route, and diagnostic context',
    (tester) async {
      final observer = OtelNavigatorObserver();

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          routes: <String, WidgetBuilder>{
            '/details': (_) => const Scaffold(body: Text('details')),
          },
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/details'),
                  child: const Text('go'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      recordFlutterFrameworkError(
        FlutterErrorDetails(
          exception: StateError('framework grouped boom'),
          stack: StackTrace.current,
          context: ErrorDescription('during grouped widget build'),
          informationCollector: () sync* {
            yield DiagnosticsNode.message('widget: DetailsScreen');
            yield DiagnosticsNode.message(
              'tree: MaterialApp > Navigator > Details',
            );
          },
        ),
        fallback: (_) {},
      );
      await Otel.forceFlush();

      final errorSpan = spanExporter.spans.singleWhere(
        (span) => span.name == 'flutter.error',
      );
      final errorLog = logExporter.logs.singleWhere(
        (log) => log.body == 'flutter.framework_error',
      );

      expect(
        errorSpan.attributes['error.group.name'],
        contains('framework:StateError'),
      );
      expect(errorSpan.attributes['flutter.route.name'], '/details');
      expect(errorSpan.attributes['screen.name'], '/details');
      expect(
        errorSpan.attributes['flutter.error.diagnostics'],
        contains('DetailsScreen'),
      );
      expect(
        errorLog.attributes['error.group.name'],
        contains('framework:StateError'),
      );
      expect(errorLog.attributes['flutter.route.name'], '/details');

      observer.dispose();
    },
  );

  test('platform errors include grouping and route context', () async {
    OtelFlutterRouteContext.update(
      routeName: '/profile',
      routeRuntimeType: 'MaterialPageRoute<dynamic>',
      previousRouteName: '/home',
    );

    recordFlutterPlatformError(
      ArgumentError('platform grouped boom'),
      StackTrace.current,
      fallback: (error, stackTrace) => false,
    );
    await Otel.forceFlush();

    final errorSpan = spanExporter.spans.singleWhere(
      (span) => span.name == 'flutter.platform_error',
    );
    final errorLog = logExporter.logs.singleWhere(
      (log) => log.body == 'flutter.platform_error',
    );

    expect(
      errorSpan.attributes['error.group.name'],
      contains('platform_dispatcher:ArgumentError'),
    );
    expect(errorSpan.attributes['flutter.route.name'], '/profile');
    expect(errorSpan.attributes['screen.previous.name'], '/home');
    expect(
      errorLog.attributes[SemanticAttributes.exceptionMessage],
      contains('platform grouped boom'),
    );
  });

  test('interaction helpers trace tap callbacks with route context', () async {
    OtelFlutterRouteContext.update(
      routeName: '/checkout',
      routeRuntimeType: 'MaterialPageRoute<dynamic>',
      previousRouteName: '/cart',
    );

    var tapped = false;
    final callback = OtelFlutterInteractions.wrapTap(
      targetName: 'checkout_button',
      attributes: const <String, Object>{'feature.flag': 'new_checkout'},
      onTap: () {
        tapped = true;
      },
    );

    callback();
    await Otel.forceFlush();

    expect(tapped, isTrue);
    final span = spanExporter.spans.singleWhere(
      (span) => span.name == 'flutter.interaction tap checkout_button',
    );
    expect(span.status, SpanStatus.ok);
    expect(span.attributes['flutter.interaction.type'], 'tap');
    expect(span.attributes['flutter.target.name'], 'checkout_button');
    expect(span.attributes['flutter.route.name'], '/checkout');
    expect(span.attributes['screen.previous.name'], '/cart');
    expect(span.attributes['feature.flag'], 'new_checkout');

    final breadcrumbs = OtelFlutterBreadcrumbs.serialize();
    expect(breadcrumbs, contains('tap checkout_button'));
  });

  test('screen span processor stamps active screen onto spans', () async {
    final exporter = InMemorySpanExporter();
    await Otel.shutdown();
    await Otel.init(
      serviceName: 'stamp-test',
      spanProcessors: <SpanProcessor>[
        OtelFlutterScreenSpanProcessor(),
        SimpleSpanProcessor(exporter),
      ],
      metricReaders: const <MetricReader>[],
      logProcessors: const <LogProcessor>[],
    );

    OtelFlutterRouteContext.update(
      routeName: '/checkout',
      routeRuntimeType: 'CheckoutRoute',
    );

    await Otel.instance.tracer.traceAsync('http-call', fn: () async {});
    await Otel.forceFlush();

    final span = exporter.lastSpanNamed('http-call');
    expect(span, isNotNull);
    expect(span!.attributes['screen.name'], '/checkout');
    expect(span.attributes['flutter.route.name'], '/checkout');

    OtelFlutterRouteContext.clear();
    await Otel.shutdown();
  });

  test(
    'screen span processor never overwrites an explicit screen.name',
    () async {
      final exporter = InMemorySpanExporter();
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'stamp-guard-test',
        spanProcessors: <SpanProcessor>[
          OtelFlutterScreenSpanProcessor(),
          SimpleSpanProcessor(exporter),
        ],
        metricReaders: const <MetricReader>[],
        logProcessors: const <LogProcessor>[],
      );

      OtelFlutterRouteContext.update(
        routeName: '/checkout',
        routeRuntimeType: 'CheckoutRoute',
      );

      // The span is born with an explicit screen.name; onStart must not clobber
      // it with the active route.
      await Otel.instance.tracer.traceAsync(
        'http-call',
        attributes: const <String, Object>{'screen.name': '/explicit'},
        fn: () async {},
      );
      await Otel.forceFlush();

      final span = exporter.lastSpanNamed('http-call');
      expect(span, isNotNull);
      expect(span!.attributes['screen.name'], '/explicit');
      // flutter.route.name was not set explicitly, so it is still stamped.
      expect(span.attributes['flutter.route.name'], '/checkout');

      OtelFlutterRouteContext.clear();
      await Otel.shutdown();
    },
  );

  test(
    'screen span processor stamps nothing when no route is active',
    () async {
      final exporter = InMemorySpanExporter();
      await Otel.shutdown();
      await Otel.init(
        serviceName: 'stamp-empty-test',
        spanProcessors: <SpanProcessor>[
          OtelFlutterScreenSpanProcessor(),
          SimpleSpanProcessor(exporter),
        ],
        metricReaders: const <MetricReader>[],
        logProcessors: const <LogProcessor>[],
      );

      OtelFlutterRouteContext.clear();

      // With no active route context, onStart must early-return without
      // throwing and leave the span unstamped.
      await Otel.instance.tracer.traceAsync('http-call', fn: () async {});
      await Otel.forceFlush();

      final span = exporter.lastSpanNamed('http-call');
      expect(span, isNotNull);
      expect(span!.attributes.containsKey('screen.name'), isFalse);
      expect(span.attributes.containsKey('flutter.route.name'), isFalse);

      OtelFlutterRouteContext.clear();
      await Otel.shutdown();
    },
  );

  test(
    'interaction helpers trace async form submissions and failures',
    () async {
      OtelFlutterRouteContext.update(
        routeName: '/payment',
        routeRuntimeType: 'MaterialPageRoute<dynamic>',
      );

      await expectLater(
        OtelFlutterInteractions.traceFormSubmit<void>(
          formName: 'payment_form',
          attributes: const <String, Object>{'flutter.form.step': 'confirm'},
          action: () async {
            throw StateError('submit boom');
          },
        ),
        throwsA(isA<StateError>()),
      );
      await Otel.forceFlush();

      final span = spanExporter.spans.singleWhere(
        (span) => span.name == 'flutter.interaction form_submit payment_form',
      );
      expect(span.status, SpanStatus.error);
      expect(span.attributes['flutter.form.name'], 'payment_form');
      expect(span.attributes['flutter.form.step'], 'confirm');
      expect(span.attributes['flutter.route.name'], '/payment');
      expect(
        span.events.any(
          (event) =>
              event.name == 'exception' &&
              event.attributes[SemanticAttributes.exceptionMessage]
                  .toString()
                  .contains('submit boom'),
        ),
        isTrue,
      );
    },
  );
}
