import 'dart:io';

Map<String, String> platformEnvironment() => Platform.environment;

String platformDefaultServiceName() {
  final executableName = _basename(Platform.resolvedExecutable);
  if (executableName.isEmpty) {
    return 'unknown_service:dart';
  }
  return 'unknown_service:$executableName';
}

Map<String, Object> detectProcessResourceAttributes() {
  return <String, Object>{
    'process.pid': pid,
    'process.executable.name': _basename(Platform.resolvedExecutable),
    'process.runtime.name': 'dart',
    'process.runtime.version': Platform.version,
    'os.type': Platform.operatingSystem,
    'os.description': Platform.operatingSystemVersion,
  };
}

Map<String, Object> detectHostResourceAttributes() {
  final hostname = Platform.localHostname;
  if (hostname.isEmpty) {
    return const <String, Object>{};
  }
  return <String, Object>{'host.name': hostname};
}

String _basename(String path) {
  final segments = path.split(RegExp(r'[\\/]'));
  return segments.isEmpty ? path : segments.last;
}
