# Frontend Note

The frontend side of the root demo currently reuses the package example app in `packages/comon_otel_flutter/example`.

That example now includes:

- tap instrumentation helpers
- form submit spans
- route transitions
- widget flow tracing
- manual HTTP propagation to the demo backend

Use the backend base URL field in the example app:

- desktop: `http://localhost:8080`
- Android emulator: `http://10.0.2.2:8080`

Press `Submit order` to create a frontend interaction span, a client request span, and a backend server span in the same distributed trace.