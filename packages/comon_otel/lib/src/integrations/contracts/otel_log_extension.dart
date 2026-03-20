import '../../context/otel_context.dart';
import '../../core/otel.dart';
import '../../core/semantic_attributes.dart';
import '../../logs/log_record.dart';
import '../../logs/logger_provider.dart';
import '../../logs/severity.dart';
import 'otel_log_bridge.dart';

/// Base class for adapting third-party logging frameworks to OpenTelemetry.
abstract class OtelLogExtension implements OtelLogBridge {
  /// Logger provider used for forwarded log records.
  LoggerProvider get loggerProvider => Otel.instance.loggerProvider;

  /// Default logger name used when none is provided.
  String get defaultLoggerName => 'comon_otel.bridge';

  /// Maps an external log level string to an OpenTelemetry severity.
  SeverityNumber mapSeverity(String level);

  @override
  /// Converts and forwards an external log event.
  void handleLog({
    required DateTime timestamp,
    required String level,
    required String message,
    String? loggerName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? extra,
  }) {
    loggerProvider.emit(
      LogRecord(
        timestamp: timestamp.toUtc(),
        observedTimestamp: DateTime.now().toUtc(),
        severity: mapSeverity(level),
        body: message,
        attributes: <String, Object>{
          ...?extra,
          if (error != null)
            SemanticAttributes.exceptionMessage: error.toString(),
          if (error != null)
            SemanticAttributes.exceptionType: error.runtimeType.toString(),
          if (stackTrace != null)
            SemanticAttributes.exceptionStacktrace: stackTrace.toString(),
        },
        resource: loggerProvider.resource,
        spanContext: OtelContext.currentSpan?.spanContext,
        loggerName: loggerName ?? defaultLoggerName,
      ),
    );
  }

  /// Convenience helper that forwards a log event using the current time.
  void forward({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String? loggerName,
    Map<String, Object>? extra,
  }) {
    handleLog(
      timestamp: DateTime.now().toUtc(),
      level: level,
      message: message,
      loggerName: loggerName,
      error: error,
      stackTrace: stackTrace,
      extra: extra,
    );
  }
}
