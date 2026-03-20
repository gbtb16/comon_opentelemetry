import '../otel_context.dart';

/// Reads and writes OpenTelemetry context data to string carriers.
abstract interface class TextMapPropagator {
  /// Injects [context] into [carrier].
  void inject(OtelContextSnapshot context, Map<String, String> carrier);

  /// Extracts an [OtelContextSnapshot] from [carrier].
  OtelContextSnapshot extract(Map<String, String> carrier);
}
