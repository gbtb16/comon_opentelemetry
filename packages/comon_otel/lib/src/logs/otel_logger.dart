import '../core/semantic_attributes.dart';
import 'log_record.dart';
import 'logger_provider.dart';
import 'severity.dart';

/// Convenience logger that emits OpenTelemetry log records.
final class OtelLogger {
  /// Creates a logger with the given [name].
  OtelLogger({required LoggerProvider provider, required this.name})
    : _provider = provider;

  final LoggerProvider _provider;

  /// Logger name recorded on emitted log records.
  final String name;

  /// Emits a fully constructed log [record].
  void emit(LogRecord record) {
    _provider.emit(record);
  }

  /// Emits a trace-level log record.
  void trace(String body, {Map<String, Object>? attributes}) {
    _emit(
      severity: SeverityNumber.trace,
      body: body,
      attributes: attributes,
      severityText: 'TRACE',
    );
  }

  /// Emits a debug-level log record.
  void debug(String body, {Map<String, Object>? attributes}) {
    _emit(
      severity: SeverityNumber.debug,
      body: body,
      attributes: attributes,
      severityText: 'DEBUG',
    );
  }

  /// Emits an info-level log record.
  void info(String body, {Map<String, Object>? attributes}) {
    _emit(
      severity: SeverityNumber.info,
      body: body,
      attributes: attributes,
      severityText: 'INFO',
    );
  }

  /// Emits a warn-level log record and optionally attaches error details.
  void warn(
    String body, {
    Map<String, Object>? attributes,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _emit(
      severity: SeverityNumber.warn,
      body: body,
      attributes: _withError(attributes, error, stackTrace),
      severityText: 'WARN',
    );
  }

  /// Emits an error-level log record and optionally attaches error details.
  void error(
    String body, {
    Map<String, Object>? attributes,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _emit(
      severity: SeverityNumber.error,
      body: body,
      attributes: _withError(attributes, error, stackTrace),
      severityText: 'ERROR',
    );
  }

  /// Emits a fatal-level log record and optionally attaches error details.
  void fatal(
    String body, {
    Map<String, Object>? attributes,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _emit(
      severity: SeverityNumber.fatal,
      body: body,
      attributes: _withError(attributes, error, stackTrace),
      severityText: 'FATAL',
    );
  }

  void _emit({
    required SeverityNumber severity,
    required String body,
    required String severityText,
    Map<String, Object>? attributes,
  }) {
    emit(
      LogRecord.current(
        severity: severity,
        severityText: severityText,
        body: body,
        attributes: attributes ?? const <String, Object>{},
        resource: _provider.resource,
        loggerName: name,
      ),
    );
  }

  Map<String, Object> _withError(
    Map<String, Object>? attributes,
    Object? error,
    StackTrace? stackTrace,
  ) {
    return <String, Object>{
      ...?attributes,
      if (error != null) SemanticAttributes.exceptionMessage: error.toString(),
      if (error != null)
        SemanticAttributes.exceptionType: error.runtimeType.toString(),
      if (stackTrace != null)
        SemanticAttributes.exceptionStacktrace: stackTrace.toString(),
    };
  }
}
