/// Single baggage entry value with optional metadata.
final class BaggageEntry {
  /// Creates a baggage entry.
  const BaggageEntry({required this.value, this.metadata});

  /// Entry value.
  final String value;

  /// Optional metadata appended to the baggage member.
  final String? metadata;
}

/// Immutable collection of baggage entries.
final class Baggage {
  /// Creates a baggage instance from pre-normalized [entries].
  const Baggage._(this.entries);

  /// Returns an empty baggage.
  factory Baggage.empty() => const Baggage._(<String, BaggageEntry>{});

  /// Baggage entries keyed by baggage member name.
  final Map<String, BaggageEntry> entries;

  /// Returns the currently active baggage.
  static Baggage get current => _currentResolver?.call() ?? Baggage.empty();

  static Baggage Function()? _currentResolver;

  /// Registers the resolver used by [current].
  static void registerCurrentResolver(Baggage Function() resolver) {
    _currentResolver = resolver;
  }

  /// Creates baggage from a map of entries.
  factory Baggage.fromEntries(Map<String, BaggageEntry> entries) {
    return Baggage._(Map<String, BaggageEntry>.unmodifiable(entries));
  }

  /// Returns the value for [key], if present.
  String? getEntry(String key) => entries[key]?.value;

  /// Returns a copy with one entry inserted or replaced.
  Baggage withEntry(String key, String value, {String? metadata}) {
    return Baggage._(<String, BaggageEntry>{
      ...entries,
      key: BaggageEntry(value: value, metadata: metadata),
    });
  }

  /// Returns a copy containing entries from both baggage values.
  Baggage merge(Baggage other) {
    return Baggage._(<String, BaggageEntry>{...entries, ...other.entries});
  }
}
