final class InstrumentationScope {
  const InstrumentationScope({
    required this.name,
    this.version,
    this.schemaUrl,
    this.attributes = const <String, Object>{},
  });

  final String name;
  final String? version;
  final String? schemaUrl;
  final Map<String, Object> attributes;

  @override
  bool operator ==(Object other) {
    if (other is! InstrumentationScope) {
      return false;
    }

    if (name != other.name ||
        version != other.version ||
        schemaUrl != other.schemaUrl ||
        attributes.length != other.attributes.length) {
      return false;
    }

    for (final entry in attributes.entries) {
      if (other.attributes[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    var hash = Object.hash(name, version, schemaUrl);
    for (final entry in attributes.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }
}
