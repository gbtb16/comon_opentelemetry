/// Typed wrapper around an 8-byte span identifier.
final class SpanId {
  /// Creates a span ID from a hexadecimal string.
  const SpanId(this._value);

  final String _value;

  /// Lowercase hexadecimal representation.
  String get hex => _value.toLowerCase();

  /// Whether this value is a valid non-zero 16-character hex span ID.
  bool get isValid => hex.length == 16 && _isHex(hex) && hex != _invalidSpanId;

  /// Parses [value] into a valid [SpanId], or returns `null`.
  static SpanId? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final spanId = SpanId(value);
    return spanId.isValid ? spanId : null;
  }

  static const String _invalidSpanId = '0000000000000000';

  @override
  String toString() => hex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SpanId && other.hex == hex;

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
