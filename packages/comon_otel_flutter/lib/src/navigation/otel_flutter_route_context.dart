/// Snapshot of the currently known Flutter route context.
final class OtelFlutterRouteContextSnapshot {
  /// Creates a route context snapshot.
  const OtelFlutterRouteContextSnapshot({
    this.routeName,
    this.routeRuntimeType,
    this.previousRouteName,
  });

  /// Current route name, if known.
  final String? routeName;

  /// Runtime type of the current route, if known.
  final String? routeRuntimeType;

  /// Previous route name, if known.
  final String? previousRouteName;

  /// Whether the snapshot contains no route information.
  bool get isEmpty =>
      routeName == null &&
      routeRuntimeType == null &&
      previousRouteName == null;
}

/// Global holder for the current Flutter route context.
final class OtelFlutterRouteContext {
  static OtelFlutterRouteContextSnapshot _current =
      const OtelFlutterRouteContextSnapshot();

  /// Current route context snapshot.
  static OtelFlutterRouteContextSnapshot get current => _current;

  /// Replaces the current route context.
  static void update({
    required String routeName,
    required String routeRuntimeType,
    String? previousRouteName,
  }) {
    _current = OtelFlutterRouteContextSnapshot(
      routeName: routeName,
      routeRuntimeType: routeRuntimeType,
      previousRouteName: previousRouteName,
    );
  }

  /// Clears the current route context.
  static void clear() {
    _current = const OtelFlutterRouteContextSnapshot();
  }
}
