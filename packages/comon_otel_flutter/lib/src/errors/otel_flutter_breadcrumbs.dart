import 'dart:collection';

import 'otel_flutter_breadcrumb_entry.dart';
import 'otel_flutter_error_hooks.dart';

/// In-memory breadcrumb buffer used by Flutter instrumentation.
final class OtelFlutterBreadcrumbs {
  static final ListQueue<OtelFlutterBreadcrumbEntry> _entries =
      ListQueue<OtelFlutterBreadcrumbEntry>();
  static bool _enabled = true;
  static int _capacity = 20;

  /// Configures breadcrumb collection.
  static void configure({required bool enabled, required int capacity}) {
    _enabled = enabled;
    _capacity = capacity < 1 ? 1 : capacity;
    while (_entries.length > _capacity) {
      _entries.removeFirst();
    }
    if (!_enabled) {
      _entries.clear();
    }
  }

  /// Adds a breadcrumb entry.
  static void add({
    required String category,
    required String message,
    Map<String, Object> attributes = const <String, Object>{},
  }) {
    if (!_enabled) {
      return;
    }

    while (_entries.length >= _capacity) {
      _entries.removeFirst();
    }
    _entries.add(
      OtelFlutterBreadcrumbEntry(
        timestamp: DateTime.now().toUtc(),
        category: category,
        message: message,
        attributes: Map<String, Object>.unmodifiable(
          Map<String, Object>.from(attributes),
        ),
      ),
    );
    OtelFlutterErrorHooks.dispatchBreadcrumb(_entries.last);
  }

  /// Returns an immutable snapshot of current breadcrumbs.
  static List<OtelFlutterBreadcrumbEntry> snapshot() {
    return List<OtelFlutterBreadcrumbEntry>.unmodifiable(_entries);
  }

  /// Serializes breadcrumbs into a compact string.
  static String? serialize() {
    if (_entries.isEmpty) {
      return null;
    }
    return _entries.map((entry) => entry.toString()).join(' | ');
  }

  /// Clears all breadcrumbs.
  static void clear() {
    _entries.clear();
  }
}
