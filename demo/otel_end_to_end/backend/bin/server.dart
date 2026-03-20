import 'dart:async';
import 'dart:io';

import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_demo_backend/demo_backend.dart';

Future<void> main() async {
  await Otel.init(
    serviceName: 'comon-otel-demo-backend',
    exporter: OtelExporter.otlpHttp,
    endpoint: 'http://localhost:4320',
  );

  final server = await DemoBackendServer.bind(
    address: InternetAddress.loopbackIPv4,
    port: 8080,
  );
  print('Demo backend listening on ${server.baseUri}');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    await Otel.shutdown();
    exit(0);
  });
}
