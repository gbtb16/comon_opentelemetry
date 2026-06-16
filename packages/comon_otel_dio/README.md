# comon_otel_dio

OpenTelemetry instrumentation for Dio built on top of `comon_otel`.

## Features

- client spans for outgoing Dio requests
- automatic W3C trace-context propagation into request headers
- HTTP semantic attributes for method, URL, route, host, status, redirects, and body sizes
- `4xx -> SpanStatus.unset`, `5xx -> SpanStatus.error`
- opt-in request and response header capture with redaction for sensitive headers
- request filtering and custom span names for noisy or domain-specific traffic

## Installation

```bash
dart pub add comon_otel_dio
```

## Quick Start

```dart
import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_dio/comon_otel_dio.dart';
import 'package:dio/dio.dart';

Future<void> main() async {
  await Otel.init(
    serviceName: 'shopping-api-client',
    exporter: OtelExporter.console,
  );

  final dio = Dio()
    ..interceptors.add(OtelDioInterceptor());

  await dio.get('https://example.com/users');
  await Otel.shutdown();
}
```

Every request produces a client span and injects the current trace context into
the outgoing headers.

## Configuration

`OtelDioInterceptor` is intentionally small and composable. The main knobs are:

- `tracerName`: overrides the instrumentation scope name used for spans
- `requestFilter`: skips span creation for selected requests
- `spanNameBuilder`: customizes span names per request
- `captureRequestHeaders`: captures selected outbound headers as span attributes
- `captureResponseHeaders`: captures selected response headers as span attributes
- `redactedHeaderValue`: replacement value for sensitive captured headers

Example with filtering, custom naming, and header capture:

```dart
final dio = Dio()
  ..interceptors.add(
    OtelDioInterceptor(
      requestFilter: (options) => !options.path.startsWith('/health'),
      // Keep span names low-cardinality: never bake a raw, unsanitized path
      // (e.g. "/order/12345") into the name — that explodes spanmetrics in the
      // collector. Use the method, or a sanitized/templated route only.
      spanNameBuilder: (options) => 'api ${options.method}',
      captureRequestHeaders: const <String>{'x-request-id'},
      captureResponseHeaders: const <String>{'content-type', 'x-request-id'},
    ),
  );
```

## Captured Attributes

The interceptor records a focused HTTP client span model out of the box.

| Attribute | When it is set |
| --- | --- |
| `http.request.method` | every request |
| `http.request.method_original` | non-standard or non-canonical methods |
| `url.full` | every request |
| `server.address` / `server.port` | when host and port are available |
| `network.protocol.name` | every request |
| `http.request.body.size` | when request body size can be estimated |
| `http.response.status_code` | when a response exists |
| `http.response.content_type` | when the response includes a content type header |
| `http.response.body.size` | when response size is known from headers or body |
| `http.resend_count` | when Dio exposes redirect history |
| `http.request.header.*` | only for explicitly captured request headers |
| `http.response.header.*` | only for explicitly captured response headers |

## Status Mapping

HTTP status codes map to span status like this:

- `1xx`, `2xx`, `3xx`: `SpanStatus.ok`
- `4xx`: `SpanStatus.unset`
- `5xx`: `SpanStatus.error`
- transport failures such as timeouts and connection errors: `SpanStatus.error`

This keeps client spans aligned with the OpenTelemetry guidance where ordinary
client-side HTTP responses are not automatically treated as telemetry errors.

## Advanced Usage

Header capture is opt-in and redacts sensitive values by default:

```dart
final dio = Dio()
  ..options.headers['authorization'] = 'Bearer secret-token'
  ..interceptors.add(
    OtelDioInterceptor(
      captureRequestHeaders: const <String>{'authorization', 'x-request-id'},
      captureResponseHeaders: const <String>{'content-type'},
    ),
  );
```

This will record:

- `http.request.header.authorization = [REDACTED]`
- `http.request.header.x_request_id = ...`
- `http.response.header.content_type = ...`

See also [example/comon_otel_dio_example.dart](example/comon_otel_dio_example.dart)
for a minimal end-to-end setup.

## Ecosystem

- [comon_otel](../comon_otel/README.md): core SDK with traces, metrics, logs, propagation, and exporters
- [comon_otel_flutter](../comon_otel_flutter/README.md): Flutter lifecycle, navigation, error, and interaction instrumentation