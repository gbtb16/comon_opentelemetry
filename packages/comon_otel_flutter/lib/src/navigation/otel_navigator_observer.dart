import 'dart:async';

import 'package:comon_otel/comon_otel.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../errors/otel_flutter_breadcrumbs.dart';
import 'otel_flutter_route_context.dart';

/// Navigator observer that records route transitions as spans and breadcrumbs.
final class OtelNavigatorObserver extends NavigatorObserver {
  /// Creates a navigator observer for route telemetry.
  OtelNavigatorObserver({
    this.spanNamePrefix = 'flutter.route',
    this.screenReadySpanNamePrefix = 'flutter.screen_ready',
    this.trackScreenReady = true,
    this.loggerName = 'comon_otel.flutter',
  });

  /// Prefix used for route transition spans.
  final String spanNamePrefix;

  /// Prefix used for screen-ready spans.
  final String screenReadySpanNamePrefix;

  /// Whether to create screen-ready spans.
  final bool trackScreenReady;

  /// Logger name used for navigation logs.
  final String loggerName;
  final Map<Route<dynamic>, Span> _activeSpans = <Route<dynamic>, Span>{};
  final Map<Route<dynamic>, Span> _screenReadySpans = <Route<dynamic>, Span>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _startRouteSpan(route, previousRoute, action: 'push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _endRouteSpan(route, previousRoute, action: 'pop');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _endRouteSpan(route, previousRoute, action: 'remove');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _endRouteSpan(oldRoute, newRoute, action: 'replace');
    }
    if (newRoute != null) {
      _startRouteSpan(newRoute, oldRoute, action: 'replace');
    }
  }

  /// Ends active spans and clears the stored route context.
  void dispose() {
    for (final span in _activeSpans.values) {
      span.setStatus(SpanStatus.ok);
      unawaited(span.end());
    }
    for (final span in _screenReadySpans.values) {
      span.setStatus(SpanStatus.ok);
      unawaited(span.end());
    }
    _activeSpans.clear();
    _screenReadySpans.clear();
    OtelFlutterRouteContext.clear();
  }

  void _startRouteSpan(
    Route<dynamic> route,
    Route<dynamic>? previousRoute, {
    required String action,
  }) {
    if (!Otel.isInitialized || _activeSpans.containsKey(route)) {
      return;
    }

    final routeName = _routeName(route);
    OtelFlutterBreadcrumbs.add(
      category: 'navigation',
      message: action,
      attributes: <String, Object>{
        'flutter.route.name': routeName,
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
      },
    );
    OtelFlutterRouteContext.update(
      routeName: routeName,
      routeRuntimeType: route.runtimeType.toString(),
      previousRouteName: previousRoute != null
          ? _routeName(previousRoute)
          : null,
    );
    final span = Otel.instance.tracer.startSpan(
      '$spanNamePrefix $routeName',
      kind: SpanKind.internal,
      attributes: <String, Object>{
        'flutter.navigation.action': action,
        'flutter.route.name': routeName,
        SemanticAttributes.flutterRoute: routeName,
        'screen.name': routeName,
        'screen.class': route.runtimeType.toString(),
        'flutter.route.runtime_type': route.runtimeType.toString(),
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
        if (previousRoute != null)
          'screen.previous.name': _routeName(previousRoute),
      },
    );

    _activeSpans[route] = span;
    _trackScreenReady(route, previousRoute, action: action);
    Otel.instance.loggerProvider
        .getLogger(loggerName)
        .debug(
          'navigation.$action',
          attributes: <String, Object>{'flutter.route.name': routeName},
        );
  }

  void _endRouteSpan(
    Route<dynamic> route,
    Route<dynamic>? previousRoute, {
    required String action,
  }) {
    OtelFlutterBreadcrumbs.add(
      category: 'navigation',
      message: action,
      attributes: <String, Object>{
        'flutter.route.name': _routeName(route),
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
      },
    );
    if (previousRoute != null) {
      OtelFlutterRouteContext.update(
        routeName: _routeName(previousRoute),
        routeRuntimeType: previousRoute.runtimeType.toString(),
      );
    } else {
      OtelFlutterRouteContext.clear();
    }

    final span = _activeSpans.remove(route);
    if (span == null) {
      return;
    }

    span.addEvent(
      'flutter.navigation.$action',
      attributes: <String, Object>{
        'flutter.route.name': _routeName(route),
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
      },
    );
    span.setStatus(SpanStatus.ok);
    unawaited(span.end());

    final readySpan = _screenReadySpans.remove(route);
    if (readySpan != null) {
      readySpan.addEvent(
        'flutter.navigation.$action',
        attributes: <String, Object>{
          'flutter.route.name': _routeName(route),
          if (previousRoute != null)
            'flutter.previous_route.name': _routeName(previousRoute),
        },
      );
      readySpan.setStatus(SpanStatus.ok);
      unawaited(readySpan.end());
    }
  }

  void _trackScreenReady(
    Route<dynamic> route,
    Route<dynamic>? previousRoute, {
    required String action,
  }) {
    if (!trackScreenReady || !Otel.isInitialized) {
      return;
    }

    final routeName = _routeName(route);
    final readySpan = Otel.instance.tracer.startSpan(
      '$screenReadySpanNamePrefix $routeName',
      kind: SpanKind.internal,
      attributes: <String, Object>{
        'flutter.navigation.action': action,
        'flutter.route.name': routeName,
        SemanticAttributes.flutterRoute: routeName,
        'screen.name': routeName,
        'screen.class': route.runtimeType.toString(),
        'flutter.route.ready': false,
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
        if (previousRoute != null)
          'screen.previous.name': _routeName(previousRoute),
      },
    );

    _screenReadySpans[route] = readySpan;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final activeSpan = _screenReadySpans.remove(route);
      if (activeSpan == null) {
        return;
      }

      OtelFlutterBreadcrumbs.add(
        category: 'navigation',
        message: 'screen_ready',
        attributes: <String, Object>{'flutter.route.name': routeName},
      );

      activeSpan.addEvent('flutter.screen_ready');
      activeSpan.setAttribute('flutter.route.ready', true);
      activeSpan.setStatus(SpanStatus.ok);
      unawaited(activeSpan.end());
    });
  }

  String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return route.runtimeType.toString();
  }
}
