/// Typed wrapper around a 16-byte trace identifier.
final class TraceId {
  /// Creates a trace ID from a hexadecimal string.
  const TraceId(this._value);

  final String _value;

  /// Lowercase hexadecimal representation.
  String get hex => _value.toLowerCase();

  /// Whether this value is a valid non-zero 32-character hex trace ID.
  bool get isValid => hex.length == 32 && _isHex(hex) && hex != _invalidTraceId;

  /// Parses [value] into a valid [TraceId], or returns `null`.
  static TraceId? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final traceId = TraceId(value);
    return traceId.isValid ? traceId : null;
  }

  static const String _invalidTraceId = '00000000000000000000000000000000';

  @override
  String toString() => hex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TraceId && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  static bool _isHex(String value) {
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final isLowerHex = codeUnit >= 0x61 && codeUnit <= 0x66;
      if (!isDigit && !isLowerHex) {
        return false;
      }
    }

    return value.isNotEmpty;
  }
}
