import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comon_otel/comon_otel.dart';

void _applyCorsHeaders(HttpResponse response) {
  response.headers
    ..set('access-control-allow-origin', '*')
    ..set('access-control-allow-methods', 'POST, OPTIONS')
    ..set(
      'access-control-allow-headers',
      'content-type, traceparent, tracestate, baggage',
    );
}

final class DemoBackendServer {
  DemoBackendServer._(this._server);

  final HttpServer _server;

  Uri get baseUri =>
      Uri.parse('http://${_server.address.address}:${_server.port}');

  static Future<DemoBackendServer> bind({
    InternetAddress? address,
    int port = 8080,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final demoServer = DemoBackendServer._(server);
    unawaited(demoServer._listen());
    return demoServer;
  }

  Future<void> close({bool force = true}) {
    return _server.close(force: force);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      await handleDemoBackendRequest(request);
    }
  }
}

Future<void> handleDemoBackendRequest(HttpRequest request) async {
  _applyCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  if (request.method == 'POST' && request.uri.path == '/submit-order') {
    final carrier = <String, String>{};
    request.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        carrier[name] = values.join(',');
      }
    });
    final parentSnapshot = Otel.propagator.extract(carrier);

    await Otel.instance.tracer.traceAsync(
      'backend.submit_order',
      parentSnapshot: parentSnapshot,
      attributes: <String, Object>{
        SemanticAttributes.httpMethod: request.method,
        SemanticAttributes.httpRoute: request.uri.path,
        SemanticAttributes.httpUrl: request.uri.toString(),
        if (parentSnapshot.traceId != null)
          'frontend.trace_id': parentSnapshot.traceId!,
      },
      fn: () async {
        final payload = await utf8.decoder.bind(request).join();
        Otel.instance.logger.info(
          'backend.order_received',
          attributes: <String, Object>{
            'payload.size': payload.length,
            'traceparent.present': carrier.containsKey('traceparent'),
          },
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object>{
              'status': 'ok',
              if (parentSnapshot.traceId != null)
                'traceId': parentSnapshot.traceId!,
            }),
          );
        await request.response.close();
      },
    );
    await Otel.forceFlush();
    return;
  }

  request.response
    ..statusCode = HttpStatus.notFound
    ..write('not found');
  await request.response.close();
}
