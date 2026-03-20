Map<String, String> platformEnvironment() => const <String, String>{};

String platformDefaultServiceName() => 'unknown_service:web';

Map<String, Object> detectProcessResourceAttributes() {
  return const <String, Object>{
    'process.runtime.name': 'dart',
    'os.type': 'web',
    'os.description': 'browser',
  };
}

Map<String, Object> detectHostResourceAttributes() {
  return const <String, Object>{};
}
