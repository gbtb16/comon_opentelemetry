# End-To-End Demo

This scaffold is the starting point for Phase 8.

## What Is Included

- `backend/` - simple Dart HTTP server instrumented with `comon_otel`
- `frontend/` - integration notes pointing to the Flutter example app
- `docker-compose.yml` - local collector and Jaeger stack
- `otel-collector-config.yaml` - OTLP receiver and exporters

## Run The Collector Stack

```bash
cd demo/otel_end_to_end
docker compose up -d
```

Jaeger UI will be available at `http://localhost:16686`.

## Run The Backend

```bash
cd demo/otel_end_to_end/backend
dart pub get
dart run bin/server.dart
```

The backend listens on `http://localhost:8080` and exposes `POST /submit-order`.

## Automated Verification

There is also an automated integration test for trace propagation:

```bash
cd demo/otel_end_to_end/backend
dart test
```

That test starts the demo backend on an ephemeral port, sends a propagated `POST /submit-order`, and verifies the backend span continues the frontend client span.

## Run The Frontend

Use the Flutter example app:

```bash
cd packages/comon_otel_flutter/example
flutter pub get
flutter run
```

Set the backend base URL in the app before pressing `Submit order`.

- Windows/macOS/Linux desktop: `http://localhost:8080`
- Android emulator: `http://10.0.2.2:8080`

The example now:

- creates frontend interaction spans
- sends `POST /submit-order`
- injects trace headers into the outgoing request
- lets the backend continue the same trace
- exports web telemetry directly to the collector over OTLP HTTP JSON

After submitting an order, open Jaeger and search for traces from either:

- `comon-otel-flutter-example`
- `comon-otel-demo-backend`