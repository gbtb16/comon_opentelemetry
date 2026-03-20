import 'dart:async';

import 'package:comon_otel/comon_otel.dart';
import 'package:flutter/widgets.dart';

/// Tracks app startup, first frame, and first interaction milestones.
final class OtelFlutterStartupTracker {
  /// Internal constructor for a startup tracker.
  OtelFlutterStartupTracker._({
    required this.loggerName,
    required this.firstFrameEventName,
    required this.firstInteractionLogName,
    required Span startupSpan,
    required bool markFirstFrame,
  }) : _startupSpan = startupSpan,
       _markFirstFrame = markFirstFrame;

  final String loggerName;
  final String firstFrameEventName;
  final String firstInteractionLogName;
  final Span _startupSpan;
  final bool _markFirstFrame;

  bool _startupCompleted = false;
  bool _firstInteractionMarked = false;

  /// Starts startup tracking when the SDK has already been initialized.
  static OtelFlutterStartupTracker? start({
    required WidgetsBinding binding,
    required String loggerName,
    required String spanName,
    required String firstFrameEventName,
    required String firstInteractionLogName,
    required bool markFirstFrame,
    DateTime? startTime,
  }) {
    if (!Otel.isInitialized) {
      return null;
    }

    final tracer = Otel.instance.tracerProvider.getTracer(
      loggerName,
      version: '0.0.1-alpha.1',
    );
    final startupSpan = tracer.startSpan(
      spanName,
      kind: SpanKind.internal,
      startTime: startTime,
      attributes: <String, Object>{'flutter.startup.completed': false},
    );

    final tracker = OtelFlutterStartupTracker._(
      loggerName: loggerName,
      firstFrameEventName: firstFrameEventName,
      firstInteractionLogName: firstInteractionLogName,
      startupSpan: startupSpan,
      markFirstFrame: markFirstFrame,
    );

    if (markFirstFrame) {
      binding.addPostFrameCallback((_) {
        unawaited(tracker.completeStartup());
      });
    }

    return tracker;
  }

  /// Completes the startup span and emits the first-frame log.
  Future<void> completeStartup() async {
    if (_startupCompleted) {
      return;
    }

    _startupCompleted = true;
    if (_markFirstFrame) {
      _startupSpan.addEvent(firstFrameEventName);
    }
    _startupSpan.setAttribute('flutter.startup.completed', true);
    await _startupSpan.end();

    if (Otel.isInitialized) {
      Otel.instance.loggerProvider
          .getLogger(loggerName)
          .info(
            'app.first_frame',
            attributes: const <String, Object>{
              'flutter.startup.completed': true,
            },
          );
    }
  }

  /// Marks the first meaningful user interaction.
  void markFirstInteraction({Map<String, Object>? attributes}) {
    if (_firstInteractionMarked || !Otel.isInitialized) {
      return;
    }

    _firstInteractionMarked = true;
    Otel.instance.loggerProvider
        .getLogger(loggerName)
        .info(
          firstInteractionLogName,
          attributes: <String, Object>{
            'flutter.interaction.first': true,
            ...?attributes,
          },
        );
  }

  /// Completes startup if it has not already finished.
  void dispose() {
    if (!_startupCompleted) {
      unawaited(completeStartup());
    }
  }
}
