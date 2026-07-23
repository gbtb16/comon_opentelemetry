/// Reads current free storage bytes, injected by the consuming app (native
/// channel). Returns `null` when the value is unavailable — the observer
/// must treat that as "skip this observation", never as zero.
typedef StorageFreeBytesGetter = Future<int?> Function();

/// Streams already-mapped thermal state strings: `nominal`/`fair`/`serious`/
/// `critical`. Mapping OS-specific values (Android's 7-level API, iOS'
/// `ProcessInfo.thermalState`) down to these 4 is the injecting app's job —
/// the fork only counts transitions between them.
typedef ThermalStateStreamGetter = Stream<String> Function();
