/// Bridge contract for forwarding external logs into OpenTelemetry logs.
abstract interface class OtelLogBridge {
  /// Forwards an external log event into the OpenTelemetry logging pipeline.
  void handleLog({
    required DateTime timestamp,
    required String level,
    required String message,
    String? loggerName,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object>? extra,
  });
}
