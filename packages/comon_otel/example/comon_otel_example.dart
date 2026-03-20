import 'package:comon_otel/comon_otel.dart';

Future<void> main() async {
  await Otel.init(
    serviceName: 'comon-otel-example',
    exporter: OtelExporter.console,
  );

  final requestCounter = Otel.instance.meter.createIntCounter(
    'example.requests',
    description: 'Counts processed example requests',
  );

  final answer = await Otel.instance.tracer.traceAsync<int>(
    'example.compute_answer',
    attributes: const <String, Object>{'example.flow': 'quickstart'},
    fn: () async {
      requestCounter.add(1, attributes: const <String, Object>{'route': '/'});
      Otel.instance.logger.info('Computing example answer');
      return 42;
    },
  );

  await Otel.forceFlush();
  print('answer: $answer');

  await Otel.shutdown();
}
