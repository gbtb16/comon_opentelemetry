import 'dart:convert';

import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_flutter/comon_otel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Otel.init(
    serviceName: 'comon-otel-flutter-example',
    exporter: kIsWeb ? OtelExporter.otlpHttpJson : OtelExporter.otlpHttp,
    endpoint: 'http://localhost:4320',
  );

  final telemetry = ComonOtelFlutter.install();
  runApp(ExampleApp(telemetry: telemetry));
}

final class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.telemetry});

  final ComonOtelFlutterInstrumentation telemetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: <NavigatorObserver>[
        if (telemetry.navigatorObserver != null) telemetry.navigatorObserver!,
      ],
      routes: <String, WidgetBuilder>{'/details': (_) => const DetailsScreen()},
      home: HomeScreen(telemetry: telemetry),
    );
  }
}

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.telemetry});

  final ComonOtelFlutterInstrumentation telemetry;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _backendUrlController = TextEditingController(
    text: 'http://localhost:8080',
  );
  String _status = 'Idle';
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _backendUrlController.dispose();
    widget.telemetry.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    setState(() {
      _submitting = true;
      _status = 'Submitting...';
    });

    try {
      widget.telemetry.markFirstInteraction(
        attributes: const <String, Object>{'flutter.interaction.type': 'tap'},
      );
      await OtelFlutterInteractions.traceFormSubmit<void>(
        formName: 'order_form',
        attributes: <String, Object>{
          'order.note_length': _controller.text.length,
        },
        action: () async {
          final backendUrl = _backendUrlController.text.trim();
          await Otel.instance.tracer.traceAsync(
            'frontend.submit_order_request',
            kind: SpanKind.client,
            attributes: <String, Object>{
              SemanticAttributes.httpMethod: 'POST',
              SemanticAttributes.httpRoute: '/submit-order',
              SemanticAttributes.httpUrl: '$backendUrl/submit-order',
            },
            fn: () async {
              final carrier = <String, String>{};
              Otel.propagator.inject(OtelContext.current, carrier);

              final response = await http.post(
                Uri.parse('$backendUrl/submit-order'),
                headers: <String, String>{
                  'content-type': 'application/json',
                  ...carrier,
                },
                body: jsonEncode(<String, Object>{
                  'note': _controller.text,
                  'submittedAt': DateTime.now().toUtc().toIso8601String(),
                }),
              );

              if (response.statusCode >= 400) {
                throw StateError(
                  'Backend responded with ${response.statusCode}: ${response.body}',
                );
              }

              if (!mounted) {
                return;
              }
              setState(() {
                _status = 'Submitted: ${response.body}';
              });
            },
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('comon_otel_flutter example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _backendUrlController,
              decoration: const InputDecoration(labelText: 'Backend base URL'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Order note'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: OtelFlutterInteractions.wrapAsyncTap(
                targetName: 'submit_order_button',
                onTap: _submitting ? () async {} : _submitOrder,
              ),
              child: Text(_submitting ? 'Submitting...' : 'Submit order'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: OtelFlutterInteractions.wrapTap(
                targetName: 'details_button',
                onTap: () {
                  Navigator.of(context).pushNamed('/details');
                },
              ),
              child: const Text('Open details'),
            ),
            const SizedBox(height: 24),
            Text('Status: $_status'),
          ],
        ),
      ),
    );
  }
}

final class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: Center(
        child: ElevatedButton(
          onPressed: OtelFlutterInteractions.wrapAsyncTap(
            targetName: 'expensive_flow_button',
            interactionType: 'tap',
            onTap: () async {
              await OtelFlutterInteractions.traceWidgetFlow<void>(
                widgetName: 'DetailsScreen',
                flowName: 'expensive_load',
                action: () async {
                  await Future<void>.delayed(const Duration(milliseconds: 80));
                },
              );
            },
          ),
          child: const Text('Run expensive flow'),
        ),
      ),
    );
  }
}
