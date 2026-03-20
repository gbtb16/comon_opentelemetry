import '../../core/semantic_attributes.dart';
import '../../logs/otel_logger.dart';

/// Emits warnings when database operations exceed a configured duration.
final class SlowQueryDetector {
  /// Creates a slow-query detector.
  const SlowQueryDetector({
    required this.logger,
    this.threshold = const Duration(milliseconds: 500),
  });

  /// Logger used for warning output.
  final OtelLogger logger;

  /// Duration above which a query is considered slow.
  final Duration threshold;

  /// Logs a warning when [duration] exceeds [threshold].
  void check({
    required String operation,
    required Duration duration,
    String? statement,
    Map<String, Object>? attributes,
  }) {
    if (duration <= threshold) {
      return;
    }

    logger.warn(
      'Slow DB query detected',
      attributes: <String, Object>{
        SemanticAttributes.dbOperation: operation,
        'db.duration_ms': duration.inMilliseconds,
        ...?statement == null
            ? null
            : <String, Object>{SemanticAttributes.dbStatement: statement},
        ...?attributes,
      },
    );
  }
}
