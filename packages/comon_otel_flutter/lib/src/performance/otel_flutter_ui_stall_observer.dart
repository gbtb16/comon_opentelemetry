import 'dart:async';

import 'package:comon_otel/comon_otel.dart';

import '../comon_otel_flutter_config.dart';
import '../errors/otel_flutter_breadcrumbs.dart';

/// Heuristic observer that detects delayed UI thread ticks.
final class OtelFlutterUiStallObserver {
  /// Creates a UI stall observer.
  OtelFlutterUiStallObserver({
    this.loggerName = 'comon_otel.flutter',
    this.durationMetricName = 'flutter.ui.stall.duration',
    this.countMetricName = 'flutter.ui.stall.count',
    this.logName = 'flutter.ui_stall',
    this.checkInterval = const Duration(milliseconds: 50),
    this.threshold = const Duration(milliseconds: 100),
    this.staticAttributes = const <String, Object>{},
    OtelFlutterNow? now,
  }) : _now = now ?? _defaultNow;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  /// Logger and meter scope name.
  final String loggerName;

  /// Metric name for stall duration.
  final String durationMetricName;

  /// Metric name for stall count.
  final String countMetricName;

  /// Log body emitted for stall warnings.
  final String logName;

  /// Poll interval used to detect delayed ticks.
  final Duration checkInterval;

  /// Minimum excess delay considered a stall.
  final Duration threshold;

  /// Static attributes merged into every recorded metric (e.g.
  /// `device.tier`). Per-record attributes win on key collision.
  final Map<String, Object> staticAttributes;
  final OtelFlutterNow _now;

  Timer? _timer;
  DateTime? _lastTickAt;
  Histogram<double>? _durationHistogramCache;
  Counter<int>? _countCounterCache;

  Histogram<double>? get _durationHistogram {
    if (!Otel.isInitialized) {
      return null;
    }

    return _durationHistogramCache ??= Otel.instance.meterProvider
        .getMeter(loggerName, version: '0.0.1-alpha.1')
        .createHistogram(
          durationMetricName,
          unit: 'ms',
          description: 'Heuristic duration of detected UI thread stalls.',
          boundaries: <double>[50, 100, 250, 500, 1000],
        );
  }

  Counter<int>? get _countCounter {
    if (!Otel.isInitialized) {
      return null;
    }

    return _countCounterCache ??= Otel.instance.meterProvider
        .getMeter(loggerName, version: '0.0.1-alpha.1')
        .createIntCounter(
          countMetricName,
          description: 'Count of heuristic UI thread stalls.',
        );
  }

  /// Starts polling for delayed UI thread ticks.
  void start() {
    if (_timer != null) {
      return;
    }

    _lastTickAt = _now();
    _timer = Timer.periodic(checkInterval, (_) {
      recordTick(_now());
    });
  }

  /// Stops polling and clears internal state.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lastTickAt = null;
  }

  /// Records one scheduler tick for stall detection.
  void recordTick([DateTime? timestamp]) {
    final now = timestamp ?? _now();
    final lastTickAt = _lastTickAt;
    _lastTickAt = now;

    if (lastTickAt == null || !Otel.isInitialized) {
      return;
    }

    final observedDelay = now.difference(lastTickAt) - checkInterval;
    if (observedDelay < threshold) {
      return;
    }

    final attributes = <String, Object>{
      ...staticAttributes,
      'flutter.ui_stall.delay_ms': observedDelay.inMicroseconds / 1000,
      'flutter.ui_stall.threshold_ms': threshold.inMicroseconds / 1000,
      'flutter.ui_stall.check_interval_ms': checkInterval.inMicroseconds / 1000,
    };

    OtelFlutterBreadcrumbs.add(
      category: 'performance',
      message: 'ui_stall',
      attributes: attributes,
    );

    _durationHistogram?.record(
      observedDelay.inMicroseconds / 1000,
      attributes: attributes,
    );
    _countCounter?.add(1, attributes: attributes);
    Otel.instance.loggerProvider
        .getLogger(loggerName)
        .warn(logName, attributes: attributes);
  }
}
