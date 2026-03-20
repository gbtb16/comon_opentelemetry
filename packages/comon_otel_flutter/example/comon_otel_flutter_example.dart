import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_flutter/comon_otel_flutter.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Otel.init(
    serviceName: 'comon-otel-flutter-example',
    exporter: OtelExporter.console,
  );

  final flutterTelemetry = ComonOtelFlutter.install();

  runApp(_ExampleApp(flutterTelemetry: flutterTelemetry));
}

final class _ExampleApp extends StatelessWidget {
  const _ExampleApp({required this.flutterTelemetry});

  final ComonOtelFlutterInstrumentation flutterTelemetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: <NavigatorObserver>[
        if (flutterTelemetry.navigatorObserver != null)
          flutterTelemetry.navigatorObserver!,
      ],
      home: Scaffold(
        appBar: AppBar(title: const Text('comon_otel_flutter example')),
        body: Center(
          child: ElevatedButton(
            onPressed: OtelFlutterInteractions.wrapTap(
              targetName: 'example_button',
              onTap: () {
                flutterTelemetry.markFirstInteraction();
              },
            ),
            child: const Text('Record interaction'),
          ),
        ),
      ),
    );
  }
}
