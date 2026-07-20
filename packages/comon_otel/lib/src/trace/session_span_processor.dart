import '../core/otel_session.dart';
import '../core/semantic_attributes.dart';
import 'span.dart';
import 'span_processor.dart';

/// Stamps every started span with the process' [OtelSession.id].
///
/// Installed unconditionally by [Otel.init], ahead of user-provided
/// processors, so `session.id` is present on every exported span
/// regardless of SDK configuration.
final class SessionSpanProcessor implements SpanProcessor {
  @override
  void onStart(Span span) {
    span.setAttribute(SemanticAttributes.sessionId, OtelSession.id);
  }

  @override
  void onEnd(Span span) {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
