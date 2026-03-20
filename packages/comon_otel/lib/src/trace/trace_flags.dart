/// Bit flags carried by a [SpanContext] and serialized in `traceparent`.
final class TraceFlags {
  /// Creates a flag set from its raw byte value.
  const TraceFlags(this.value) : assert(value >= 0 && value <= 0xff);

  /// Raw flag byte.
  final int value;

  /// No flags set.
  static const TraceFlags none = TraceFlags(0x00);

  /// Only the sampled bit set.
  static const TraceFlags sampled = TraceFlags(0x01);

  /// Only the random bit set.
  static const TraceFlags random = TraceFlags(0x02);

  /// Both sampled and random bits set.
  static const TraceFlags sampledAndRandom = TraceFlags(0x03);

  /// Whether the sampled bit is set.
  bool get isSampled => (value & 0x01) == 0x01;

  /// Whether the random bit is set.
  bool get isRandom => (value & 0x02) == 0x02;

  /// Lowercase two-character hexadecimal representation.
  String get hex => value.toRadixString(16).padLeft(2, '0');

  /// Builds flags from sampled and random booleans.
  factory TraceFlags.fromSampled(bool sampled, {bool random = false}) {
    final value = (sampled ? 0x01 : 0x00) | (random ? 0x02 : 0x00);
    return TraceFlags(value);
  }

  /// Parses a two-character hexadecimal trace-flags string.
  static TraceFlags? tryParseHex(String? value) {
    if (value == null || value.length != 2) {
      return null;
    }

    final normalized = value.toLowerCase();
    if (!_isHex(normalized)) {
      return null;
    }

    return TraceFlags(int.parse(normalized, radix: 16));
  }

  @override
  String toString() => hex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TraceFlags && other.value == value;

  @override
  int get hashCode => value.hashCode;

  static bool _isHex(String value) {
    for (final codeUnit in value.codeUnits) {
      final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
      final isLowerHex = codeUnit >= 0x61 && codeUnit <= 0x66;
      if (!isDigit && !isLowerHex) {
        return false;
      }
    }

    return true;
  }
}
