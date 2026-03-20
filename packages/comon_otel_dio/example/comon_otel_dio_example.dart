import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_dio/comon_otel_dio.dart';
import 'package:dio/dio.dart';

Future<void> main() async {
  await Otel.init(
    serviceName: 'comon-otel-dio-example',
    exporter: OtelExporter.console,
  );

  final dio = Dio()
    ..interceptors.add(
      OtelDioInterceptor(
        captureRequestHeaders: const <String>{'x-request-id'},
        captureResponseHeaders: const <String>{'content-type'},
      ),
    );

  try {
    final response = await dio.get<dynamic>(
      'https://httpbin.org/get',
      options: Options(
        headers: const <String, String>{'x-request-id': 'example-request-1'},
      ),
    );

    print('Response status: ${response.statusCode}');
  } finally {
    await Otel.shutdown();
  }
}
