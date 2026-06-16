import 'package:comon_otel/comon_otel.dart';

import 'otel_flutter_route_context.dart';

/// Span processor that stamps the active Flutter screen name onto every span
/// at start time, including spans created by other packages (e.g. Dio HTTP
/// client spans). This is how screen <-> interaction <-> HTTP correlation is
/// delivered "por atributo" without coupling the HTTP layer to Flutter.
final class OtelFlutterScreenSpanProcessor implements SpanProcessor {
  /// Creates a screen-stamping span processor.
  const OtelFlutterScreenSpanProcessor({
    this.screenNameAttribute = 'screen.name',
    this.routeNameAttribute = 'flutter.route.name',
  });

  /// Attribute key used for the active screen name.
  final String screenNameAttribute;

  /// Attribute key used for the active route name.
  final String routeNameAttribute;

  @override
  void onStart(Span span) {
    final routeName = OtelFlutterRouteContext.current.routeName;
    if (routeName == null || routeName.isEmpty) {
      return;
    }
    // `span.attributes` returns a fresh unmodifiable copy on each call, so read
    // it once. Stamp BOTH `screen.name` and `flutter.route.name` with the same
    // route value on purpose: dashboards can correlate on either key. An
    // explicit value set at span creation wins — we never clobber it.
    final attributes = span.attributes;
    if (!attributes.containsKey(screenNameAttribute)) {
      span.setAttribute(screenNameAttribute, routeName);
    }
    if (!attributes.containsKey(routeNameAttribute)) {
      span.setAttribute(routeNameAttribute, routeName);
    }
  }

  @override
  void onEnd(Span span) {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
