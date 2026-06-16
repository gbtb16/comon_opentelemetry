import 'package:flutter/foundation.dart';

import 'errors/otel_flutter_error_hooks.dart';

/// Clock source used by Flutter instrumentation components.
typedef OtelFlutterNow = DateTime Function();

@immutable
/// Configuration for installing Flutter-specific telemetry instrumentation.
final class ComonOtelFlutterConfig {
  /// Creates a Flutter instrumentation configuration.
  const ComonOtelFlutterConfig({
    this.captureFlutterErrors = true,
    this.capturePlatformDispatcherErrors = true,
    this.observeAppLifecycle = true,
    this.trackNavigatorRoutes = true,
    this.logLifecycleTransitions = true,
    this.trackAppStartup = true,
    this.markFirstFrame = true,
    this.trackScreenReady = true,
    this.trackLifecycleDurations = true,
    this.trackFrameTimings = true,
    this.trackMemoryPressureMetrics = true,
    this.trackUiStalls = true,
    this.trackBreadcrumbs = true,
    this.breadcrumbListener,
    this.frameworkErrorListener,
    this.platformErrorListener,
    this.routeSpanNamePrefix = 'flutter.route',
    this.screenReadySpanNamePrefix = 'flutter.screen_ready',
    this.appStartupSpanName = 'app.startup',
    this.firstFrameEventName = 'flutter.first_frame',
    this.firstInteractionLogName = 'app.first_interaction',
    this.frameDurationMetricName = 'flutter.frame.duration',
    this.buildDurationMetricName = 'flutter.build.duration',
    this.rasterDurationMetricName = 'flutter.raster.duration',
    this.foregroundDurationMetricName = 'app.foreground.duration',
    this.backgroundDurationMetricName = 'app.background.duration',
    this.memoryPressureCountMetricName = 'app.memory_pressure.count',
    this.slowFrameCountMetricName = 'flutter.frame.slow.count',
    this.jankFrameCountMetricName = 'flutter.frame.jank.count',
    this.uiStallDurationMetricName = 'flutter.ui.stall.duration',
    this.uiStallCountMetricName = 'flutter.ui.stall.count',
    this.uiStallLogName = 'flutter.ui_stall',
    this.slowFrameThreshold = const Duration(milliseconds: 16),
    this.jankFrameThreshold = const Duration(milliseconds: 32),
    this.uiStallCheckInterval = const Duration(milliseconds: 50),
    this.uiStallThreshold = const Duration(milliseconds: 100),
    this.breadcrumbCapacity = 20,
    this.appStartupStartTime,
    this.now,
    this.loggerName = 'comon_otel.flutter',
  });

  /// Whether to capture framework errors routed through `FlutterError.onError`.
  final bool captureFlutterErrors;

  /// Whether to capture platform dispatcher errors.
  final bool capturePlatformDispatcherErrors;

  /// Whether to observe app lifecycle callbacks.
  final bool observeAppLifecycle;

  /// Whether to install the navigator observer for route tracking.
  final bool trackNavigatorRoutes;

  /// Whether to log lifecycle transitions.
  final bool logLifecycleTransitions;

  /// Whether to create startup instrumentation.
  final bool trackAppStartup;

  /// Whether startup tracking should add a first-frame event.
  final bool markFirstFrame;

  /// Whether to create route-level screen-ready spans.
  final bool trackScreenReady;

  /// Whether to record foreground and background durations.
  final bool trackLifecycleDurations;

  /// Whether to record frame timing metrics.
  final bool trackFrameTimings;

  /// Whether to count memory pressure callbacks.
  final bool trackMemoryPressureMetrics;

  /// Whether to detect heuristic UI stalls.
  final bool trackUiStalls;

  /// Whether to collect breadcrumbs for navigation, lifecycle, and errors.
  final bool trackBreadcrumbs;

  /// Optional listener invoked for each recorded breadcrumb.
  final OtelFlutterBreadcrumbListener? breadcrumbListener;

  /// Optional listener invoked for captured framework errors.
  final OtelFlutterErrorListener? frameworkErrorListener;

  /// Optional listener invoked for captured platform dispatcher errors.
  final OtelFlutterErrorListener? platformErrorListener;

  /// Prefix that was used for the long-lived route-transition span.
  ///
  /// Retained for API/binary compatibility but currently inert: that
  /// umbrella span is no longer created (it was a tracing anti-pattern and
  /// embedded high-cardinality route names). Only the short screen-ready
  /// span, named via [screenReadySpanNamePrefix], is emitted now.
  final String routeSpanNamePrefix;

  /// Prefix used for screen-ready spans.
  final String screenReadySpanNamePrefix;

  /// Span name used for startup tracking.
  final String appStartupSpanName;

  /// Event name emitted when the first frame is rendered.
  final String firstFrameEventName;

  /// Log name emitted for the first user interaction.
  final String firstInteractionLogName;

  /// Metric name for total frame duration.
  final String frameDurationMetricName;

  /// Metric name for build duration.
  final String buildDurationMetricName;

  /// Metric name for raster duration.
  final String rasterDurationMetricName;

  /// Metric name for foreground duration.
  final String foregroundDurationMetricName;

  /// Metric name for background duration.
  final String backgroundDurationMetricName;

  /// Metric name for memory pressure count.
  final String memoryPressureCountMetricName;

  /// Metric name for slow frame count.
  final String slowFrameCountMetricName;

  /// Metric name for jank frame count.
  final String jankFrameCountMetricName;

  /// Metric name for UI stall duration.
  final String uiStallDurationMetricName;

  /// Metric name for UI stall count.
  final String uiStallCountMetricName;

  /// Log name emitted when a UI stall is detected.
  final String uiStallLogName;

  /// Threshold for classifying a frame as slow.
  final Duration slowFrameThreshold;

  /// Threshold for classifying a frame as janky.
  final Duration jankFrameThreshold;

  /// Poll interval used by the UI stall observer.
  final Duration uiStallCheckInterval;

  /// Minimum delayed tick classified as a UI stall.
  final Duration uiStallThreshold;

  /// Maximum number of breadcrumbs retained in memory.
  final int breadcrumbCapacity;

  /// Optional explicit app startup start time.
  final DateTime? appStartupStartTime;

  /// Optional clock override, mainly for tests.
  final OtelFlutterNow? now;

  /// Logger and meter scope name used by Flutter instrumentation.
  final String loggerName;
}
