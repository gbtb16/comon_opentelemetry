import 'dart:collection';

/// A single key/value member inside a W3C `tracestate` header.
final class TraceStateMember {
  /// Creates a tracestate member.
  const TraceStateMember({required this.key, required this.value});

  /// Member key.
  final String key;

  /// Member value.
  final String value;

  /// Normalized `key=value` representation.
  String get normalized => '${key.trim()}=${value.trim()}';

  @override
  String toString() => normalized;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceStateMember &&
          other.key.trim() == key.trim() &&
          other.value.trim() == value.trim();

  @override
  int get hashCode => Object.hash(key.trim(), value.trim());
}

/// Parsed representation of a W3C `tracestate` header value.
final class TraceState {
  /// Creates a tracestate wrapper from its serialized value.
  const TraceState(this._value);

  final String _value;

  /// Trimmed serialized value.
  String get value => _value.trim();

  /// Normalized serialized value, or `null` when invalid.
  String? get normalized => _normalize(_value);

  /// Parsed tracestate members when [normalized] is valid.
  List<TraceStateMember>? get members {
    final normalized = this.normalized;
    if (normalized == null) {
      return null;
    }

    return UnmodifiableListView<TraceStateMember>(
      normalized.split(',').map(_parseNormalizedMember).toList(growable: false),
    );
  }

  /// Returns the member for [key], if present.
  TraceStateMember? operator [](String key) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }

    for (final member in members ?? const <TraceStateMember>[]) {
      if (member.key == normalizedKey) {
        return member;
      }
    }

    return null;
  }

  /// Whether the serialized tracestate is valid per the supported constraints.
  bool get isValid => normalized != null;

  /// Parses [value] into a normalized [TraceState], or returns `null`.
  static TraceState? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final traceState = TraceState(value);
    return traceState.isValid ? TraceState(traceState.normalized!) : null;
  }

  /// Builds a [TraceState] from already separated members.
  static TraceState? tryFromMembers(Iterable<TraceStateMember> members) {
    final normalizedMembers = members
        .map((member) => _normalizeMember(member.normalized))
        .toList(growable: false);
    if (normalizedMembers.any((member) => member == null)) {
      return null;
    }

    final joined = normalizedMembers.cast<String>().join(',');
    return tryParse(joined);
  }

  /// Builds a [TraceState] from members or throws a [FormatException].
  factory TraceState.fromMembers(Iterable<TraceStateMember> members) {
    final traceState = tryFromMembers(members);
    if (traceState == null) {
      throw FormatException('Invalid tracestate members');
    }

    return traceState;
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TraceState && other.value == value;

  @override
  int get hashCode => value.hashCode;

  static TraceStateMember _parseNormalizedMember(String normalizedMember) {
    final separatorIndex = normalizedMember.indexOf('=');
    return TraceStateMember(
      key: normalizedMember.substring(0, separatorIndex),
      value: normalizedMember.substring(separatorIndex + 1),
    );
  }

  static String? _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 512) {
      return null;
    }

    final normalizedMembers = <String>[];
    for (final member in trimmed.split(',')) {
      final normalizedMember = _normalizeMember(member);
      if (normalizedMember == null) {
        return null;
      }
      normalizedMembers.add(normalizedMember);
    }

    if (normalizedMembers.isEmpty || normalizedMembers.length > 32) {
      return null;
    }

    return normalizedMembers.join(',');
  }

  static String? _normalizeMember(String rawMember) {
    final member = rawMember.trim();
    if (member.isEmpty) {
      return null;
    }

    final separatorIndex = member.indexOf('=');
    if (separatorIndex <= 0 || separatorIndex == member.length - 1) {
      return null;
    }

    final key = member.substring(0, separatorIndex).trim();
    final value = member.substring(separatorIndex + 1).trim();
    if (!_isValidKey(key) || !_isValidValue(value)) {
      return null;
    }

    return '$key=$value';
  }

  static bool _isValidKey(String key) {
    if (key.isEmpty || key.length > 256) {
      return false;
    }

    final parts = key.split('@');
    if (parts.length > 2 || parts.any((part) => part.isEmpty)) {
      return false;
    }

    return parts.every(_isValidKeyPart);
  }

  static bool _isValidKeyPart(String value) {
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final isLowerAlpha = codeUnit >= 0x61 && codeUnit <= 0x7a;
      const allowedPunctuation = <int>{0x5f, 0x2d, 0x2a, 0x2f};
      if (!isDigit && !isLowerAlpha && !allowedPunctuation.contains(codeUnit)) {
        return false;
      }
    }

    return true;
  }

  static bool _isValidValue(String value) {
    if (value.isEmpty || value.length > 256) {
      return false;
    }

    for (final codeUnit in value.codeUnits) {
      final isPrintableAscii = codeUnit >= 0x20 && codeUnit <= 0x7e;
      if (!isPrintableAscii || codeUnit == 0x2c) {
        return false;
      }
    }

    return true;
  }
}
