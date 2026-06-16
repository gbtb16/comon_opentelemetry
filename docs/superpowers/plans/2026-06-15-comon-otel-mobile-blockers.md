# comon_otel Mobile-Readiness Blockers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the six go-live blockers (B1–B6) that make the `comon_otel` fork unsafe for a production Flutter mobile app, plus the strongly-recommended PII fix (F2.1), all upstream in the fork.

**Architecture:** Three packages in one workspace — `comon_otel` (core SDK), `comon_otel_flutter` (Flutter instrumentation), `comon_otel_dio` (HTTP interceptor). Fixes are surgical and isolated to the failure paths the audit found: export-chain resilience (B1), reachable batching config (B3), lifecycle flush + metric reader (B2), Dio safety + cardinality (B5/B6), screen-correlation model (B4, Opção A), and resource/PII hygiene (F2.1). Every fix is test-first.

**Tech Stack:** Dart 3.9, Flutter ≥3.24, `package:test` (core/dio), `flutter_test` (flutter), `dio`. Test pattern in core is a single `comon_otel_test.dart` entrypoint with `part` files exposing `defineXxxTests()`; flutter/dio packages use standalone test files with self-contained fakes.

**Decisions locked (from the spec + this session):**
- All fixes land **in the fork** (`serezhia/comon_opentelemetry`); the app depends on the corrected HEAD.
- **B4 = Opção A:** remove the long-lived "umbrella" route span, keep only the short `screen_ready` transition span, sanitize route names against cardinality, **and** add the screen-name stamping `SpanProcessor` so HTTP spans carry `screen.name` (intra-app correlation). The `mobile → backend` W3C stitch is already done by the Dio interceptor's `inject` — this plan does not touch it.
- **F2.1 included** (host.name PII + resource completeness), per the spec's "fortemente recomendado".
- B1 swallows export errors (chain must always resolve); SDK-level error reporting is **out of scope** (that is F2.2, deferred). No existing test asserts `forceFlush` throws on export failure, so swallowing is safe.

**Out of scope (separate plan later):** F2.2–F2.7 and the entire Phase 3 roadmap.

---

## Prerequisites (read before running any test step)

This is a **melos pub-workspace** (`resolution: workspace`; root `pubspec.yaml` lists the three packages + a `melos:` block). Two consequences the executor must respect:

1. **Toolchain: Flutter 3.38.9, pinned via fvm (`.fvmrc` at the fork root), NOT the app's 3.35.7.** Verified empirically: with Flutter 3.35.7 the workspace **fails to resolve** — `comon_otel` has a dev_dependency `test: ^1.26.3` (min `test_api 0.7.7`), but `flutter_test` from Flutter 3.35.7 pins `test_api 0.7.6`. CI (`.github/workflows/ci.yml`) uses `flutter-version: 3.38.9`, which bundles a compatible `test_api`. The fork now pins it: `.fvmrc` → `{"flutter": "3.38.9"}`. Run `fvm use 3.38.9` once (installs if missing). fvm is per-project, so this does not affect the app's 3.35.7. (3.38.3 — Dart 3.10.1, already installed locally — also resolves; edit `.fvmrc` if you want to skip the download.) Do **not** run tests with 3.35.7.

   > **This toolchain requirement is for developing/testing the fork only.** Consuming `comon_otel*` in the Prolog app is unaffected: `test` is a *dev_dependency* of the fork (not resolved by consumers), and the packages' SDK constraints (`sdk: ^3.9.0`, `flutter: >=3.24.0`) are satisfied by the app's 3.35.7. The one runtime impact on the app is the two deps added in Task 8 (`device_info_plus`, `package_info_plus`) — match the app's existing majors.

2. **Bootstrap at the root first; per-package `dart test` standalone does not resolve.** Before any test step, run from the fork root (all melos/dart/flutter invocations go through `fvm` so they use the pinned 3.38.9):

   ```bash
   fvm dart pub get            # fetches melos (a root dev_dependency)
   fvm dart run melos bootstrap
   ```

   The per-task run commands work **after** bootstrap, prefixed with `fvm` (`cd packages/comon_otel && fvm dart test ...`, `cd packages/comon_otel_flutter && fvm flutter test ...`) — they are exactly what melos invokes per package. Canonical whole-suite commands (what CI runs):

   ```bash
   fvm dart run melos run analyze
   fvm dart run melos run test        # = test:dart (dart test) + test:flutter (flutter test)
   ```

   When a task says "Run the full core suite", `fvm dart run melos run test:dart` is equivalent; "full flutter suite" ↔ `fvm dart run melos run test:flutter`. (Each task's run lines omit the `fvm` prefix for brevity — apply it.)

> Note on exports: `lib/src/core/core.dart` does `export 'resource.dart';` (whole-file), so the `TelemetrySdkResourceDetector` added in Task 8 is auto-exported — Task 8 Step 4 is a confirmation, not new wiring. `ProcessResourceDetector`/`ResourceDetector` are likewise already public via that export.

---

## File Structure

**`comon_otel` (core)**
- Modify: `lib/src/trace/batch_span_processor.dart` — wrap flush body in try/catch (B1).
- Modify: `lib/src/logs/batch_log_processor.dart` — same (B1).
- Modify: `lib/src/core/otel.dart` — expose processor/reader knobs + `serviceVersion` + `resourceDetectors` in `init` (B3, F2.1).
- Modify: `lib/src/core/resource.dart` — `serviceVersion` on `autoDetect`; add `TelemetrySdkResourceDetector` (F2.1).
- Modify: `lib/src/core/core.dart` — export the new detector (F2.1).
- Test: `test/common/test_support.dart` — add `_ThrowOnceSpanExporter`/`_ThrowOnceLogExporter` (B1).
- Test: `test/src/signals_pipeline_tests.dart` — B1 recovery tests.
- Test: `test/src/config_resource_tests.dart` — B3 config-flow + F2.1 resource tests.

**`comon_otel_dio`**
- Modify: `lib/src/otel_dio_interceptor.dart` — try/catch around all telemetry, always call `handler.next` (B5); drop `http.route` (B6).
- Test: `test/comon_otel_dio_test.dart` — B5 safety test; update two existing tests for B6.

**`comon_otel_flutter`**
- Modify: `lib/src/lifecycle/otel_flutter_binding_observer.dart` — flush on background (B2).
- Modify: `lib/src/navigation/otel_navigator_observer.dart` — remove umbrella span, sanitize route names (B4a).
- Create: `lib/src/navigation/otel_flutter_screen_span_processor.dart` — screen.name stamping processor (B4b).
- Create: `lib/src/resource/mobile_resource_detector.dart` — mobile resource attributes helper (F2.1).
- Modify: `lib/comon_otel_flutter.dart` — export the new processor + resource helper (B4b, F2.1).
- Modify: `pubspec.yaml` — add `device_info_plus`, `package_info_plus` (F2.1).
- Test: `test/comon_otel_flutter_test.dart` — B2, B4a, B4b, F2.1-pure tests + self-contained fakes.

---

## Task 1: B1 — Flush-chain poisoning (span + log processors)

**Severity: CRITICAL.** A throwing flush body (e.g. timeout on slow mobile networks) leaves `_pendingFlush` permanently rejected; all subsequent flushes short-circuit and telemetry stops forever.

**Files:**
- Test: `packages/comon_otel/test/common/test_support.dart`
- Test: `packages/comon_otel/test/src/signals_pipeline_tests.dart`
- Modify: `packages/comon_otel/lib/src/trace/batch_span_processor.dart:69-94`
- Modify: `packages/comon_otel/lib/src/logs/batch_log_processor.dart:78-103`

- [ ] **Step 1: Add throw-once fakes to test support**

Append to `packages/comon_otel/test/common/test_support.dart`:

```dart
final class _ThrowOnceSpanExporter implements SpanExporter {
  int exportCalls = 0;
  final List<SpanData> exported = <SpanData>[];

  @override
  Future<ExportResult> export(List<SpanData> spans) async {
    exportCalls += 1;
    if (exportCalls == 1) {
      throw TimeoutException('simulated export timeout');
    }
    exported.addAll(spans);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

final class _ThrowOnceLogExporter implements LogExporter {
  int exportCalls = 0;
  final List<LogRecord> exported = <LogRecord>[];

  @override
  Future<ExportResult> export(List<LogRecord> logs) async {
    exportCalls += 1;
    if (exportCalls == 1) {
      throw TimeoutException('simulated export timeout');
    }
    exported.addAll(logs);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
```

- [ ] **Step 2: Write the failing tests**

Add to the `group('signals and pipeline', ...)` body in `packages/comon_otel/test/src/signals_pipeline_tests.dart`:

```dart
test('batch span processor recovers after a flush export throws', () async {
  final throwingExporter = _ThrowOnceSpanExporter();
  final processor = BatchSpanProcessor(
    exporter: throwingExporter,
    maxBatchSize: 1000,
    scheduleDelay: const Duration(minutes: 1),
  );

  await Otel.shutdown();
  await Otel.init(
    serviceName: 'test-service',
    spanProcessors: <SpanProcessor>[processor],
    metricReaders: <MetricReader>[
      ExportingMetricReader(exporter: metricExporter),
    ],
    logProcessors: <LogProcessor>[SimpleLogProcessor(logExporter)],
  );

  await Otel.instance.tracer.traceAsync('first-span', fn: () async {});
  // First flush hits the throwing export; the fix must swallow it so the
  // chain stays alive.
  await processor.forceFlush().catchError((_) {});

  await Otel.instance.tracer.traceAsync('second-span', fn: () async {});
  await processor.forceFlush();

  expect(
    throwingExporter.exported.any((span) => span.name == 'second-span'),
    isTrue,
  );
});

test('batch log processor recovers after a flush export throws', () async {
  final throwingExporter = _ThrowOnceLogExporter();
  final processor = BatchLogProcessor(
    exporter: throwingExporter,
    maxBatchSize: 1000,
    scheduleDelay: const Duration(minutes: 1),
  );

  await Otel.shutdown();
  await Otel.init(
    serviceName: 'test-service',
    spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
    metricReaders: <MetricReader>[
      ExportingMetricReader(exporter: metricExporter),
    ],
    logProcessors: <LogProcessor>[processor],
  );

  Otel.instance.logger.info('first-log');
  await processor.forceFlush().catchError((_) {});

  Otel.instance.logger.info('second-log');
  await processor.forceFlush();

  expect(
    throwingExporter.exported.any((log) => log.body == 'second-log'),
    isTrue,
  );
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart -n "recovers after a flush export throws"`
Expected: FAIL — second flush rethrows the poisoned future / `second-span` and `second-log` never exported.

- [ ] **Step 4: Fix `BatchSpanProcessor._flushBatch`**

In `packages/comon_otel/lib/src/trace/batch_span_processor.dart`, replace the `_flushBatch` body (lines 69-94):

```dart
  Future<void> _flushBatch({bool all = false}) {
    _pendingFlush = _pendingFlush.then((_) async {
      try {
        if (_queue.isEmpty) {
          return;
        }

        do {
          final batch = <SpanData>[];
          final limit = all ? _queue.length : maxBatchSize;
          while (_queue.isNotEmpty && batch.length < limit) {
            batch.add(_queue.removeFirst());
          }

          if (batch.isNotEmpty) {
            final exportFuture = _exporter.export(batch);
            if (exportTimeout == null) {
              await exportFuture;
            } else {
              await exportFuture.timeout(exportTimeout!);
            }
          }
        } while (all && _queue.isNotEmpty);
      } catch (_) {
        // Swallow export failures so the flush chain never becomes a
        // permanently-rejected Future. SDK-level error reporting is tracked
        // separately (F2.2, out of scope here).
      }
    });

    return _pendingFlush;
  }
```

- [ ] **Step 5: Fix `BatchLogProcessor._flushBatch`**

In `packages/comon_otel/lib/src/logs/batch_log_processor.dart`, replace the `_flushBatch` body (lines 78-103) with the identical pattern, using `LogRecord` instead of `SpanData`:

```dart
  Future<void> _flushBatch({bool all = false}) {
    _pendingFlush = _pendingFlush.then((_) async {
      try {
        if (_queue.isEmpty) {
          return;
        }

        do {
          final batch = <LogRecord>[];
          final limit = all ? _queue.length : maxBatchSize;
          while (_queue.isNotEmpty && batch.length < limit) {
            batch.add(_queue.removeFirst());
          }

          if (batch.isNotEmpty) {
            final exportFuture = _exporter.export(batch);
            if (exportTimeout == null) {
              await exportFuture;
            } else {
              await exportFuture.timeout(exportTimeout!);
            }
          }
        } while (all && _queue.isNotEmpty);
      } catch (_) {
        // Swallow export failures so the flush chain never becomes a
        // permanently-rejected Future. SDK-level error reporting is tracked
        // separately (F2.2, out of scope here).
      }
    });

    return _pendingFlush;
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart -n "recovers after a flush export throws"`
Expected: PASS (both tests).

- [ ] **Step 7: Run the full core suite (no regressions)**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/comon_otel/lib/src/trace/batch_span_processor.dart \
        packages/comon_otel/lib/src/logs/batch_log_processor.dart \
        packages/comon_otel/test/common/test_support.dart \
        packages/comon_otel/test/src/signals_pipeline_tests.dart
git commit -F - <<'EOF'
fix(core): keep batch flush chain alive after export failure (B1)

A throwing flush body left _pendingFlush permanently rejected, silently
stopping all traces/logs. Wrap the flush body in try/catch so the chain
always resolves.
EOF
```

---

## Task 2: B3 — Expose batching/metric-reader knobs on `Otel.init`

**Severity: HIGH.** `OtelConfig` already carries these fields, but `Otel.init` only populates them from env vars, which are empty on Flutter mobile (`--dart-define` does not populate `Platform.environment`). Result: default falls to `SimpleSpanProcessor` (one HTTP POST per span). Expose the knobs as explicit `init` parameters that override the env defaults.

**Files:**
- Modify: `packages/comon_otel/lib/src/core/otel.dart:80-219`
- Test: `packages/comon_otel/test/src/config_resource_tests.dart`

- [ ] **Step 1: Write the failing test**

Add to the relevant `group` in `packages/comon_otel/test/src/config_resource_tests.dart`:

```dart
test('init exposes batch and metric-reader configuration explicitly', () async {
  await Otel.shutdown();
  await Otel.init(
    serviceName: 'test-service',
    useBatchSpanProcessor: true,
    batchSpanProcessorScheduleDelay: const Duration(seconds: 2),
    batchSpanProcessorMaxQueueSize: 128,
    batchSpanProcessorMaxExportBatchSize: 64,
    useBatchLogProcessor: true,
    batchLogProcessorScheduleDelay: const Duration(seconds: 3),
    usePeriodicMetricReader: true,
    metricExportInterval: const Duration(seconds: 30),
  );

  final config = Otel.instance.config;
  expect(config.useBatchSpanProcessor, isTrue);
  expect(config.batchSpanProcessorScheduleDelay, const Duration(seconds: 2));
  expect(config.batchSpanProcessorMaxQueueSize, 128);
  expect(config.batchSpanProcessorMaxExportBatchSize, 64);
  expect(config.useBatchLogProcessor, isTrue);
  expect(config.batchLogProcessorScheduleDelay, const Duration(seconds: 3));
  expect(config.usePeriodicMetricReader, isTrue);
  expect(config.metricExportInterval, const Duration(seconds: 30));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart -n "exposes batch and metric-reader configuration"`
Expected: FAIL — compile error, named parameters `useBatchSpanProcessor`, etc. are not defined on `Otel.init`.

- [ ] **Step 3: Add the parameters to `Otel.init`**

In `packages/comon_otel/lib/src/core/otel.dart`, add these named parameters to the `init({...})` signature (insert after `SpanLimits spanLimits = const SpanLimits(),` at line 94):

```dart
    bool? useBatchSpanProcessor,
    Duration? batchSpanProcessorScheduleDelay,
    Duration? batchSpanProcessorExportTimeout,
    int? batchSpanProcessorMaxQueueSize,
    int? batchSpanProcessorMaxExportBatchSize,
    bool? useBatchLogProcessor,
    Duration? batchLogProcessorScheduleDelay,
    Duration? batchLogProcessorExportTimeout,
    int? batchLogProcessorMaxQueueSize,
    int? batchLogProcessorMaxExportBatchSize,
    bool? usePeriodicMetricReader,
    Duration? metricExportInterval,
    Duration? metricExportTimeout,
```

- [ ] **Step 4: Wire the parameters into `OtelConfig` (override env defaults)**

In the same file, in the `OtelConfig(...)` construction (lines 207-219), replace those lines so explicit params take priority over env:

```dart
      useBatchSpanProcessor:
          useBatchSpanProcessor ?? OtelEnvConfig.hasBspConfig,
      batchSpanProcessorScheduleDelay:
          batchSpanProcessorScheduleDelay ?? OtelEnvConfig.bspScheduleDelay,
      batchSpanProcessorExportTimeout:
          batchSpanProcessorExportTimeout ?? OtelEnvConfig.bspExportTimeout,
      batchSpanProcessorMaxQueueSize:
          batchSpanProcessorMaxQueueSize ?? OtelEnvConfig.bspMaxQueueSize,
      batchSpanProcessorMaxExportBatchSize:
          batchSpanProcessorMaxExportBatchSize ??
          OtelEnvConfig.bspMaxExportBatchSize,
      useBatchLogProcessor:
          useBatchLogProcessor ?? OtelEnvConfig.hasBlrpConfig,
      batchLogProcessorScheduleDelay:
          batchLogProcessorScheduleDelay ?? OtelEnvConfig.blrpScheduleDelay,
      batchLogProcessorExportTimeout:
          batchLogProcessorExportTimeout ?? OtelEnvConfig.blrpExportTimeout,
      batchLogProcessorMaxQueueSize:
          batchLogProcessorMaxQueueSize ?? OtelEnvConfig.blrpMaxQueueSize,
      batchLogProcessorMaxExportBatchSize:
          batchLogProcessorMaxExportBatchSize ??
          OtelEnvConfig.blrpMaxExportBatchSize,
      usePeriodicMetricReader:
          usePeriodicMetricReader ?? OtelEnvConfig.hasMetricReaderConfig,
      metricExportInterval:
          metricExportInterval ?? OtelEnvConfig.metricExportInterval,
      metricExportTimeout:
          metricExportTimeout ?? OtelEnvConfig.metricExportTimeout,
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart -n "exposes batch and metric-reader configuration"`
Expected: PASS.

- [ ] **Step 6: Run the full core suite**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart`
Expected: PASS (env-driven defaults still work because explicit params default to `null`).

- [ ] **Step 7: Commit**

```bash
git add packages/comon_otel/lib/src/core/otel.dart \
        packages/comon_otel/test/src/config_resource_tests.dart
git commit -F - <<'EOF'
feat(core): expose batch/metric-reader knobs on Otel.init (B3)

Env vars are empty on Flutter mobile, so the only way to enable batching
was unreachable. Add explicit init params that override env defaults.
EOF
```

---

## Task 3: B5 — Dio interceptor must never break the real request

**Severity: HIGH (production safety).** No `try/catch` around span creation/inject. If any telemetry call throws, `handler.next(...)` is never reached and the user's request hangs/fails. Wrap all telemetry in try/catch and always forward the request.

**Files:**
- Modify: `packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart:78-182`
- Test: `packages/comon_otel_dio/test/comon_otel_dio_test.dart`

- [ ] **Step 1: Write the failing test**

Add inside `main()` in `packages/comon_otel_dio/test/comon_otel_dio_test.dart`:

```dart
test('request proceeds even when instrumentation throws', () async {
  final dio = Dio()
    ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
      return ResponseBody.fromString('ok', 200);
    })
    ..interceptors.add(
      OtelDioInterceptor(
        spanNameBuilder: (_) => throw StateError('instrumentation boom'),
      ),
    );

  final response = await dio.get<dynamic>('https://example.com/users');
  expect(response.statusCode, 200);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/comon_otel_dio && dart test -n "request proceeds even when instrumentation throws"`
Expected: FAIL — `StateError` propagates out of `onRequest`; `handler.next` never called, the `get` future completes with an error.

- [ ] **Step 3: Refactor `onRequest` to isolate telemetry and always forward**

In `packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart`, replace `onRequest` (lines 78-142) with:

```dart
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      if (Otel.isInitialized && (requestFilter?.call(options) ?? true)) {
        _startRequestSpan(options);
      }
    } catch (_) {
      // Instrumentation must never break the real request.
    }
    handler.next(options);
  }

  void _startRequestSpan(RequestOptions options) {
    final uri = options.uri;
    final originalMethod = options.method;
    final method = originalMethod.toUpperCase();
    final requestBodySize = _estimateBodySize(options.data);
    final attributes = <String, Object>{
      SemanticAttributes.httpMethod: method,
      SemanticAttributes.httpUrl: uri.toString(),
      SemanticAttributes.netPeerName: uri.host,
      if (uri.hasPort) SemanticAttributes.netPeerPort: uri.port,
      SemanticAttributes.networkProtocolName: uri.scheme,
      if (_shouldCaptureOriginalMethod(originalMethod, method))
        SemanticAttributes.httpMethodOriginal: originalMethod,
    };
    if (requestBodySize != null) {
      attributes[SemanticAttributes.httpRequestBodySize] = requestBodySize;
    }

    final span = Otel.instance.tracerProvider
        .getTracer(tracerName, version: '0.0.1-alpha.1')
        .startSpan(
          spanNameBuilder(options),
          kind: SpanKind.client,
          parentSnapshot: OtelContext.current,
          attributes: attributes,
        );

    options.extra[_spanExtraKey] = span;

    final carrier = <String, String>{
      for (final entry in options.headers.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
    Otel.propagator.inject(
      OtelContextSnapshot(
        spanContext: span.spanContext,
        baggage: OtelContext.currentBaggage,
      ),
      carrier,
    );
    options.headers.addAll(carrier);

    final capturedRequestHeaders = <String, Object>{};
    _addCapturedHeaderAttributes(
      capturedRequestHeaders,
      <String, List<String>>{
        for (final entry in options.headers.entries)
          entry.key: <String>[if (entry.value != null) entry.value.toString()],
      },
      prefix: 'http.request.header.',
      allowList: captureRequestHeaders,
    );
    for (final entry in capturedRequestHeaders.entries) {
      span.setAttribute(entry.key, entry.value);
    }
  }
```

> Note: the `SemanticAttributes.httpRoute` line is intentionally absent here — it is removed by B6 (Task 4). If you implement B6 first, this already matches; if not, the line stays removed regardless.

- [ ] **Step 4: Wrap `onResponse` telemetry**

Replace `onResponse` (lines 144-157) with:

```dart
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    try {
      final span = _takeSpan(response.requestOptions);
      if (span != null) {
        _applyResponseMetadata(span, response);
        _applyHttpStatus(span, response.statusCode);
        unawaited(span.end());
      }
    } catch (_) {
      // Instrumentation must never break the real response.
    }
    handler.next(response);
  }
```

- [ ] **Step 5: Wrap `onError` telemetry**

Replace `onError` (lines 159-182) with:

```dart
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final span = _takeSpan(err.requestOptions);
      if (span != null) {
        final response = err.response;
        final statusCode = response?.statusCode;
        if (response != null) {
          _applyResponseMetadata(span, response);
        }
        final shouldRecordException = statusCode == null || statusCode >= 500;
        if (shouldRecordException) {
          span.recordException(err, stackTrace: err.stackTrace);
          span.setStatus(
            SpanStatus.error,
            description: err.message ?? err.toString(),
          );
        } else {
          _applyHttpStatus(span, statusCode);
        }
        unawaited(span.end());
      }
    } catch (_) {
      // Instrumentation must never break error propagation.
    }
    handler.next(err);
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/comon_otel_dio && dart test -n "request proceeds even when instrumentation throws"`
Expected: PASS.

- [ ] **Step 7: Run the full dio suite**

Run: `cd packages/comon_otel_dio && dart test`
Expected: PASS (all pre-existing behavior preserved).

- [ ] **Step 8: Commit**

```bash
git add packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart \
        packages/comon_otel_dio/test/comon_otel_dio_test.dart
git commit -F - <<'EOF'
fix(dio): never let instrumentation break the real request (B5)

Wrap span/inject logic in try/catch and always call handler.next so a
telemetry failure can no longer hang or fail the user's HTTP request.
EOF
```

---

## Task 4: B6 — Drop client-side `http.route` (Mimir cardinality)

**Severity: HIGH (shared-infra damage).** The Dio client emits `http.route` = raw `uri.path` (with IDs like `/users/12345`). `http.route` is an allowed spanmetrics dimension, so the high-cardinality filter does **not** drop it → each ID becomes a new metric series and pollutes Mimir for the whole company. The backend already emits the correct templated `http.route`. Stop emitting it on the client.

**Files:**
- Modify: `packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart` (the `_startRequestSpan` attributes map from Task 3, or line 92 if Task 3 not yet applied)
- Test: `packages/comon_otel_dio/test/comon_otel_dio_test.dart:57,251-264`

- [ ] **Step 1: Update the existing tests to expect no client `http.route`**

In `packages/comon_otel_dio/test/comon_otel_dio_test.dart`, in the test `'interceptor injects propagation headers and records success'`, replace the line:

```dart
    expect(span.attributes[SemanticAttributes.httpRoute], '/users');
```

with:

```dart
    expect(span.attributes.containsKey(SemanticAttributes.httpRoute), isFalse);
```

In the test `'concurrent requests keep spans isolated'`, replace the map-building and assertions (lines 251-263) that key by `httpRoute` with keying by `httpUrl`:

```dart
    final spansByUrl = <String, SpanData>{
      for (final span in spanExporter.spans)
        span.attributes[SemanticAttributes.httpUrl]! as String: span,
    };
    expect(
      spansByUrl.keys,
      containsAll(<String>[
        'https://example.com/slow',
        'https://example.com/fast',
      ]),
    );
    expect(
      spansByUrl['https://example.com/slow']
          ?.attributes[SemanticAttributes.httpUrl],
      'https://example.com/slow',
    );
    expect(
      spansByUrl['https://example.com/fast']
          ?.attributes[SemanticAttributes.httpUrl],
      'https://example.com/fast',
    );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/comon_otel_dio && dart test -n "records success"`
Expected: FAIL — the span still carries `http.route` = `/users` (not yet removed).

- [ ] **Step 3: Remove the `http.route` attribute from the client span**

In `packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart`, in the `attributes` map inside `_startRequestSpan` (added in Task 3), delete the line:

```dart
      SemanticAttributes.httpRoute: uri.path.isEmpty ? '/' : uri.path,
```

(If Task 3 has not been applied yet, this is line 92 of the original `onRequest`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/comon_otel_dio && dart test -n "records success"`
Then: `cd packages/comon_otel_dio && dart test -n "concurrent requests keep spans isolated"`
Expected: PASS (both).

- [ ] **Step 5: Run the full dio suite**

Run: `cd packages/comon_otel_dio && dart test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart \
        packages/comon_otel_dio/test/comon_otel_dio_test.dart
git commit -F - <<'EOF'
fix(dio): stop emitting client-side http.route (B6)

Raw uri.path as http.route explodes spanmetrics cardinality in Mimir.
The backend already emits the correct templated route; drop it on the
client. url.full still carries the concrete URL on the trace.
EOF
```

---

## Task 5: B2 — Flush on background + periodic metric reader

**Severity: CRITICAL.** (1) The lifecycle observer never calls `Otel.forceFlush()` on `paused`/`detached`/`hidden`, so the in-memory queue (and the crash that just happened) dies when the OS suspends the app. (2) The default metric reader (`ExportingMetricReader`) has no timer, so metrics are never exported unless someone calls `forceFlush`.

Part (1) is a code fix in the Flutter lifecycle observer. Part (2) is satisfied by the B3 knob (`usePeriodicMetricReader`) plus the `forceFlush` added in (1): a true automatic "mobile default" is not feasible in core without coupling to Flutter, so the contract is **app-side init config**, documented here.

**Files:**
- Modify: `packages/comon_otel_flutter/lib/src/lifecycle/otel_flutter_binding_observer.dart`
- Test: `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`

- [ ] **Step 1: Add a self-contained counting exporter to the flutter test**

In `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`, ensure these imports exist at the top (add any that are missing):

```dart
import 'dart:async';

import 'package:comon_otel/comon_otel.dart';
import 'package:comon_otel_flutter/comon_otel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
```

Add this fake near the top of the file (outside `main`):

```dart
final class _CountingSpanExporter implements SpanExporter {
  int forceFlushCount = 0;
  final List<SpanData> spans = <SpanData>[];

  @override
  Future<ExportResult> export(List<SpanData> data) async {
    spans.addAll(data);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {
    forceFlushCount += 1;
  }

  @override
  Future<void> shutdown() async {}
}
```

- [ ] **Step 2: Write the failing test**

Add inside `main()`:

```dart
test('flushes telemetry when the app is backgrounded', () async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final exporter = _CountingSpanExporter();
  await Otel.shutdown();
  await Otel.init(
    serviceName: 'lifecycle-test',
    spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
    metricReaders: const <MetricReader>[],
    logProcessors: const <LogProcessor>[],
  );

  final observer = OtelFlutterBindingObserver();
  observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
  observer.didChangeAppLifecycleState(AppLifecycleState.paused);

  // Let the unawaited forceFlush microtask run.
  await Future<void>.delayed(Duration.zero);

  expect(exporter.forceFlushCount, greaterThanOrEqualTo(1));

  await Otel.shutdown();
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "flushes telemetry when the app is backgrounded"`
Expected: FAIL — `forceFlushCount` is 0; the observer never flushes on `paused`.

- [ ] **Step 4: Add the background flush to the observer**

In `packages/comon_otel_flutter/lib/src/lifecycle/otel_flutter_binding_observer.dart`, add `import 'dart:async';` at the top (for `unawaited`). Then, in `didChangeAppLifecycleState` (lines 96-121), add the flush after the existing logic, before `_lastLifecycleState = state;`:

```dart
    if (Otel.isInitialized && _isBackgrounding(state)) {
      // The only reliable point to drain the in-memory queue before the OS
      // suspends or kills the process.
      unawaited(Otel.forceFlush());
    }

    _lastLifecycleState = state;
  }

  bool _isBackgrounding(AppLifecycleState state) {
    return state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
  }
```

(The closing brace shown belongs to `didChangeAppLifecycleState`; add `_isBackgrounding` as a new method right after it.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "flushes telemetry when the app is backgrounded"`
Expected: PASS.

- [ ] **Step 6: Document the mobile metric-reader contract**

In `packages/comon_otel_flutter/README.md`, add a short "Mobile init recommendations" note stating that mobile apps must enable batching and the periodic metric reader explicitly, since env vars are unavailable:

```markdown
## Mobile init recommendations

On Flutter mobile, environment variables do not reach the SDK, so enable
batching and periodic metric export explicitly:

    await Otel.init(
      serviceName: 'my-app',
      exporter: OtelExporter.otlpHttpJson,
      tracesEndpoint: 'https://collector.example.com/otel/http/v1/traces',
      // ...per-signal endpoints + auth headers...
      useBatchSpanProcessor: true,
      useBatchLogProcessor: true,
      usePeriodicMetricReader: true,
      metricExportInterval: const Duration(seconds: 60),
    );

Without `usePeriodicMetricReader: true`, metrics are only exported on
`forceFlush()` (e.g. on app background) and never on a timer.
```

- [ ] **Step 7: Run the full flutter suite**

Run: `cd packages/comon_otel_flutter && flutter test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/comon_otel_flutter/lib/src/lifecycle/otel_flutter_binding_observer.dart \
        packages/comon_otel_flutter/test/comon_otel_flutter_test.dart \
        packages/comon_otel_flutter/README.md
git commit -F - <<'EOF'
fix(flutter): flush telemetry on app background (B2)

Drain the in-memory queue on paused/detached/hidden before the OS kills
the process. Document the mobile init contract for the periodic metric
reader (env vars are unavailable on mobile; the B3 knob must be set).
EOF
```

---

## Task 6: B4a — Remove the umbrella route span + sanitize route names

**Severity: HIGH.** The long-lived route span (push→pop, minutes/hours) is a tracing anti-pattern, was never activated as a parent anyway, and embeds the raw route name (cardinality risk). Opção A: keep only the short `screen_ready` span as the screen-transition span, and sanitize route names so dynamic IDs collapse to `:id`.

**Files:**
- Modify: `packages/comon_otel_flutter/lib/src/navigation/otel_navigator_observer.dart`
- Test: `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`

- [ ] **Step 1: Write the failing test**

Add inside `main()` in `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`:

```dart
testWidgets('navigation emits only a sanitized screen_ready span', (
  tester,
) async {
  final exporter = _CountingSpanExporter();
  await Otel.shutdown();
  await Otel.init(
    serviceName: 'nav-test',
    spanProcessors: <SpanProcessor>[SimpleSpanProcessor(exporter)],
    metricReaders: const <MetricReader>[],
    logProcessors: const <LogProcessor>[],
  );

  final observer = OtelNavigatorObserver();
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/order/12345'),
    builder: (_) => const SizedBox.shrink(),
  );

  observer.didPush(route, null);
  await tester.pump(); // fires the post-frame callback that ends screen_ready
  await Otel.forceFlush();

  final names = exporter.spans.map((span) => span.name).toList();
  expect(names, contains('flutter.screen_ready /order/:id'));
  expect(
    names.any((name) => name.startsWith('flutter.route ')),
    isFalse,
    reason: 'umbrella route span must no longer be created',
  );
  expect(
    names.any((name) => name.contains('12345')),
    isFalse,
    reason: 'route names must be sanitized against cardinality',
  );

  observer.dispose();
  await Otel.shutdown();
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "navigation emits only a sanitized screen_ready span"`
Expected: FAIL — a `flutter.route /order/12345` umbrella span is emitted and the name is not sanitized.

- [ ] **Step 3: Sanitize route names at the source**

In `packages/comon_otel_flutter/lib/src/navigation/otel_navigator_observer.dart`, replace `_routeName` (lines 228-234) with:

```dart
  String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      return _sanitizeRouteName(name);
    }
    return route.runtimeType.toString();
  }

  String _sanitizeRouteName(String name) {
    if (!name.startsWith('/')) {
      return name;
    }
    final numericSegment = RegExp(r'^\d+$');
    final uuidSegment = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    final segments = name.split('/').map((segment) {
      if (segment.isEmpty) {
        return segment;
      }
      if (numericSegment.hasMatch(segment) || uuidSegment.hasMatch(segment)) {
        return ':id';
      }
      return segment;
    });
    return segments.join('/');
  }
```

- [ ] **Step 4: Remove the umbrella route span**

In the same file:

1. Delete the `_activeSpans` field (line 31):

```dart
  final Map<Route<dynamic>, Span> _activeSpans = <Route<dynamic>, Span>{};
```

2. Replace `_startRouteSpan` (lines 74-125) so it keeps breadcrumb, route-context update, screen-ready tracking, and the debug log, but creates **no** long-lived span:

```dart
  void _startRouteSpan(
    Route<dynamic> route,
    Route<dynamic>? previousRoute, {
    required String action,
  }) {
    if (!Otel.isInitialized) {
      return;
    }

    final routeName = _routeName(route);
    OtelFlutterBreadcrumbs.add(
      category: 'navigation',
      message: action,
      attributes: <String, Object>{
        'flutter.route.name': routeName,
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
      },
    );
    OtelFlutterRouteContext.update(
      routeName: routeName,
      routeRuntimeType: route.runtimeType.toString(),
      previousRouteName: previousRoute != null
          ? _routeName(previousRoute)
          : null,
    );
    _trackScreenReady(route, previousRoute, action: action);
    Otel.instance.loggerProvider
        .getLogger(loggerName)
        .debug(
          'navigation.$action',
          attributes: <String, Object>{'flutter.route.name': routeName},
        );
  }
```

3. Replace `_endRouteSpan` (lines 127-179) so it keeps breadcrumb + route-context update + screen-ready cleanup, but no longer touches `_activeSpans`:

```dart
  void _endRouteSpan(
    Route<dynamic> route,
    Route<dynamic>? previousRoute, {
    required String action,
  }) {
    OtelFlutterBreadcrumbs.add(
      category: 'navigation',
      message: action,
      attributes: <String, Object>{
        'flutter.route.name': _routeName(route),
        if (previousRoute != null)
          'flutter.previous_route.name': _routeName(previousRoute),
      },
    );
    if (previousRoute != null) {
      OtelFlutterRouteContext.update(
        routeName: _routeName(previousRoute),
        routeRuntimeType: previousRoute.runtimeType.toString(),
      );
    } else {
      OtelFlutterRouteContext.clear();
    }

    final readySpan = _screenReadySpans.remove(route);
    if (readySpan != null) {
      readySpan.addEvent(
        'flutter.navigation.$action',
        attributes: <String, Object>{
          'flutter.route.name': _routeName(route),
          if (previousRoute != null)
            'flutter.previous_route.name': _routeName(previousRoute),
        },
      );
      readySpan.setStatus(SpanStatus.ok);
      unawaited(readySpan.end());
    }
  }
```

4. Replace `dispose` (lines 60-72) so it no longer iterates `_activeSpans`:

```dart
  /// Ends active screen-ready spans and clears the stored route context.
  void dispose() {
    for (final span in _screenReadySpans.values) {
      span.setStatus(SpanStatus.ok);
      unawaited(span.end());
    }
    _screenReadySpans.clear();
    OtelFlutterRouteContext.clear();
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "navigation emits only a sanitized screen_ready span"`
Expected: PASS.

- [ ] **Step 6: Run the full flutter suite + analyzer**

Run: `cd packages/comon_otel_flutter && flutter test`
Then: `cd packages/comon_otel_flutter && flutter analyze`
Expected: PASS, no analyzer errors (confirm `_activeSpans` has no remaining references and the unused `spanNamePrefix` field, if now unused, is handled — keep the field; it is still a public constructor param).

> If `flutter analyze` flags `spanNamePrefix` as unused, leave the field (it is part of the public constructor API and config) — reference it in a doc comment if needed, but do not remove the parameter.

- [ ] **Step 7: Commit**

```bash
git add packages/comon_otel_flutter/lib/src/navigation/otel_navigator_observer.dart \
        packages/comon_otel_flutter/test/comon_otel_flutter_test.dart
git commit -F - <<'EOF'
fix(flutter): drop umbrella route span, sanitize route names (B4a)

Opção A: keep only the short screen_ready transition span; the long-lived
route span was an anti-pattern and was never activated as a parent.
Sanitize dynamic route segments to :id to protect cardinality.
EOF
```

---

## Task 7: B4b — Stamp `screen.name` onto every span (intra-app correlation)

**Severity: HIGH (delivers the B4 correlation value).** HTTP spans are created in `comon_otel_dio`, which cannot see `OtelFlutterRouteContext` (no dependency on `comon_otel_flutter`). A `SpanProcessor` registered in the Flutter app stamps `screen.name` in `onStart` from the active route context — it runs in the shared core pipeline for **all** spans, including Dio's, without coupling the packages.

**Files:**
- Create: `packages/comon_otel_flutter/lib/src/navigation/otel_flutter_screen_span_processor.dart`
- Modify: `packages/comon_otel_flutter/lib/comon_otel_flutter.dart` (export)
- Test: `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`

- [ ] **Step 1: Write the failing test**

Add inside `main()`:

```dart
test('screen span processor stamps active screen onto spans', () async {
  final exporter = InMemorySpanExporter();
  await Otel.shutdown();
  await Otel.init(
    serviceName: 'stamp-test',
    spanProcessors: <SpanProcessor>[
      OtelFlutterScreenSpanProcessor(),
      SimpleSpanProcessor(exporter),
    ],
    metricReaders: const <MetricReader>[],
    logProcessors: const <LogProcessor>[],
  );

  OtelFlutterRouteContext.update(
    routeName: '/checkout',
    routeRuntimeType: 'CheckoutRoute',
  );

  await Otel.instance.tracer.traceAsync('http-call', fn: () async {});
  await Otel.forceFlush();

  final span = exporter.lastSpanNamed('http-call');
  expect(span, isNotNull);
  expect(span!.attributes['screen.name'], '/checkout');

  OtelFlutterRouteContext.clear();
  await Otel.shutdown();
});
```

> `OtelFlutterRouteContext` must be exported by the package — confirm in Step 3 that `comon_otel_flutter.dart` exports it (it is referenced by tests). If not exported, add it to the export list alongside the new processor.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "screen span processor stamps active screen onto spans"`
Expected: FAIL — compile error: `OtelFlutterScreenSpanProcessor` is undefined.

- [ ] **Step 3: Create the processor**

Create `packages/comon_otel_flutter/lib/src/navigation/otel_flutter_screen_span_processor.dart`:

```dart
import 'package:comon_otel/comon_otel.dart';

import 'otel_flutter_route_context.dart';

/// Span processor that stamps the active Flutter screen name onto every span
/// at start time, including spans created by other packages (e.g. Dio HTTP
/// client spans). This is how screen <-> interaction <-> HTTP correlation is
/// delivered "por atributo" without coupling the HTTP layer to Flutter.
final class OtelFlutterScreenSpanProcessor implements SpanProcessor {
  /// Creates a screen-stamping span processor.
  const OtelFlutterScreenSpanProcessor({
    this.screenNameAttribute = 'screen.name',
    this.routeNameAttribute = 'flutter.route.name',
  });

  /// Attribute key used for the active screen name.
  final String screenNameAttribute;

  /// Attribute key used for the active route name.
  final String routeNameAttribute;

  @override
  void onStart(Span span) {
    final routeName = OtelFlutterRouteContext.current.routeName;
    if (routeName == null || routeName.isEmpty) {
      return;
    }
    if (!span.attributes.containsKey(screenNameAttribute)) {
      span.setAttribute(screenNameAttribute, routeName);
    }
    if (!span.attributes.containsKey(routeNameAttribute)) {
      span.setAttribute(routeNameAttribute, routeName);
    }
  }

  @override
  void onEnd(Span span) {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
```

- [ ] **Step 4: Export the processor (and route context if needed)**

In `packages/comon_otel_flutter/lib/comon_otel_flutter.dart`, add:

```dart
export 'src/navigation/otel_flutter_screen_span_processor.dart';
```

Confirm `export 'src/navigation/otel_flutter_route_context.dart';` is also present; if absent, add it (the stamping test and app wiring need `OtelFlutterRouteContext`).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "screen span processor stamps active screen onto spans"`
Expected: PASS.

- [ ] **Step 6: Document the wiring**

In `packages/comon_otel_flutter/README.md`, under the mobile init note from Task 5, add that the app must include the processor in `Otel.init`:

```markdown
To correlate HTTP and interaction spans with the active screen, add the
screen span processor to your processors (alongside your exporter
processor):

    spanProcessors: <SpanProcessor>[
      OtelFlutterScreenSpanProcessor(),
      BatchSpanProcessor(exporter: mySpanExporter),
    ],
```

- [ ] **Step 7: Run the full flutter suite + analyzer**

Run: `cd packages/comon_otel_flutter && flutter test && flutter analyze`
Expected: PASS, no analyzer errors.

- [ ] **Step 8: Commit**

```bash
git add packages/comon_otel_flutter/lib/src/navigation/otel_flutter_screen_span_processor.dart \
        packages/comon_otel_flutter/lib/comon_otel_flutter.dart \
        packages/comon_otel_flutter/test/comon_otel_flutter_test.dart \
        packages/comon_otel_flutter/README.md
git commit -F - <<'EOF'
feat(flutter): stamp screen.name onto all spans (B4b)

A SpanProcessor in the Flutter package stamps the active screen onto every
span at onStart, including Dio HTTP spans, delivering screen<->HTTP
correlation across the package boundary without coupling Dio to Flutter.
EOF
```

---

## Task 8: F2.1 — Resource completeness + `host.name` PII

**Severity: HIGH (privacy + spec-required resource fields).** `host.name = Platform.localHostname` leaks user PII on mobile ("iPhone de João"). The resource is also missing `telemetry.sdk.*` (spec-mandatory), `service.version`, and `device.*`/`os.name`/`os.version`. Add `serviceVersion` and a `resourceDetectors` override to `init` (so mobile can omit `HostResourceDetector`), add a `TelemetrySdkResourceDetector` to core, and provide a mobile resource-attributes helper in the Flutter package.

**Files:**
- Modify: `packages/comon_otel/lib/src/core/resource.dart`
- Modify: `packages/comon_otel/lib/src/core/core.dart` (export the new detector if not already covered by `resource.dart` export)
- Modify: `packages/comon_otel/lib/src/core/otel.dart` (init params: `serviceVersion`, `resourceDetectors`)
- Create: `packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart`
- Modify: `packages/comon_otel_flutter/lib/comon_otel_flutter.dart` (export)
- Modify: `packages/comon_otel_flutter/pubspec.yaml` (deps)
- Test: `packages/comon_otel/test/src/config_resource_tests.dart`
- Test: `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`

- [ ] **Step 1: Write the failing core test**

Add to `packages/comon_otel/test/src/config_resource_tests.dart`:

```dart
test('omitting HostResourceDetector keeps host.name out of the resource', () async {
  await Otel.shutdown();
  await Otel.init(
    serviceName: 'pii-test',
    serviceVersion: '1.2.3',
    resourceDetectors: const <ResourceDetector>[
      ProcessResourceDetector(),
      TelemetrySdkResourceDetector(),
    ],
  );

  final attributes = Otel.instance.tracerProvider.resource.attributes;
  expect(attributes.containsKey('host.name'), isFalse);
  expect(attributes['service.version'], '1.2.3');
  expect(attributes['telemetry.sdk.name'], 'comon_otel');
  expect(attributes['telemetry.sdk.language'], 'dart');
  expect(attributes['telemetry.sdk.version'], isNotEmpty);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart -n "keeps host.name out of the resource"`
Expected: FAIL — compile error: `serviceVersion`/`resourceDetectors` params and `TelemetrySdkResourceDetector` are undefined.

- [ ] **Step 3: Add `serviceVersion` to `Resource.autoDetect` and the SDK detector**

In `packages/comon_otel/lib/src/core/resource.dart`:

1. Add the `serviceVersion` parameter to `autoDetect` (signature lines 81-87) and pass it through:

```dart
  factory Resource.autoDetect({
    required String serviceName,
    String? serviceVersion,
    String? environment,
    String? schemaUrl,
    Iterable<ResourceDetector>? detectors,
    Map<String, Object>? extra,
  }) {
    final detectedAttributes = <String, Object>{};
    for (final detector in detectors ?? defaultDetectors) {
      detectedAttributes.addAll(detector.detect());
    }
    detectedAttributes.remove('service.name');
    if (environment != null) {
      detectedAttributes.remove('deployment.environment');
    }

    return Resource(
      serviceName: serviceName,
      serviceVersion: serviceVersion,
      environment: environment,
      schemaUrl: schemaUrl,
      extra: <String, Object>{...detectedAttributes, ...?extra},
    );
  }
```

2. Add the SDK detector class after `HostResourceDetector` (after line 29):

```dart
/// Detects OpenTelemetry SDK identity attributes (spec-mandatory).
final class TelemetrySdkResourceDetector implements ResourceDetector {
  /// Creates a telemetry SDK resource detector.
  const TelemetrySdkResourceDetector();

  @override
  Map<String, Object> detect() {
    return const <String, Object>{
      'telemetry.sdk.name': 'comon_otel',
      'telemetry.sdk.language': 'dart',
      'telemetry.sdk.version': '0.0.1-alpha.1',
    };
  }
}
```

- [ ] **Step 4: Confirm the detector is exported**

`packages/comon_otel/lib/src/core/core.dart` should export `resource.dart` (which now contains `TelemetrySdkResourceDetector`). Verify `ResourceDetector`, `ProcessResourceDetector`, and the new `TelemetrySdkResourceDetector` are reachable from `package:comon_otel/comon_otel.dart`. If `core.dart` exports symbols explicitly, add `TelemetrySdkResourceDetector` to that list.

Run: `cd packages/comon_otel && dart analyze lib/src/core/resource.dart`
Expected: No errors.

- [ ] **Step 5: Add `serviceVersion` + `resourceDetectors` to `Otel.init`**

In `packages/comon_otel/lib/src/core/otel.dart`:

1. Add params to the `init({...})` signature (after `String serviceName = '',` at line 81):

```dart
    String? serviceVersion,
    List<ResourceDetector>? resourceDetectors,
```

2. Add the `resource.dart` import if `ResourceDetector` is not already imported — it is imported transitively via `resource.dart` (line 40 imports `'resource.dart'`); confirm `ResourceDetector` resolves. If not, add `import '../core/resource.dart';` is already present (line 40 `import 'resource.dart';`).

3. Pass them into `Resource.autoDetect` (lines 243-248):

```dart
    final resource = Resource.autoDetect(
      serviceName: resolvedServiceName,
      serviceVersion: serviceVersion,
      environment: environment,
      schemaUrl: resourceSchemaUrl,
      detectors: resourceDetectors,
      extra: resolvedResourceAttributes,
    );
```

- [ ] **Step 6: Run the core test to verify it passes**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart -n "keeps host.name out of the resource"`
Expected: PASS.

- [ ] **Step 7: Run the full core suite**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart`
Expected: PASS (default behavior unchanged — `resourceDetectors` defaults to `null` → `defaultDetectors`).

- [ ] **Step 8: Add the Flutter mobile resource helper (pure mapping + async wrapper)**

Create `packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart`:

```dart
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Builds OTel resource attributes from already-resolved device/app values.
///
/// Kept pure (no platform channels) so it is unit-testable. The async
/// [detectMobileResourceAttributes] resolves the raw values and delegates here.
Map<String, Object> mobileResourceAttributesFrom({
  required String osName,
  required String osVersion,
  String? deviceModelIdentifier,
  String? deviceManufacturer,
  String? serviceVersion,
}) {
  return <String, Object>{
    'os.name': osName,
    'os.version': osVersion,
    if (deviceModelIdentifier != null && deviceModelIdentifier.isNotEmpty)
      'device.model.identifier': deviceModelIdentifier,
    if (deviceManufacturer != null && deviceManufacturer.isNotEmpty)
      'device.manufacturer': deviceManufacturer,
    if (serviceVersion != null && serviceVersion.isNotEmpty)
      'service.version': serviceVersion,
  };
}

/// Resolves device and app metadata into OTel resource attributes.
///
/// Pass the result to `Otel.init(resourceAttributes: ...)`, and omit
/// `HostResourceDetector` from `resourceDetectors` to avoid leaking the
/// device host name (PII) on mobile.
Future<Map<String, Object>> detectMobileResourceAttributes() async {
  final deviceInfo = DeviceInfoPlugin();
  final packageInfo = await PackageInfo.fromPlatform();

  final baseInfo = await deviceInfo.deviceInfo;
  final data = baseInfo.data;

  // device_info_plus exposes platform-specific maps; read defensively.
  final osName = (data['name'] as String?) ?? '';
  final osVersion =
      (data['systemVersion'] as String?) ??
      (data['version']?.toString()) ??
      '';
  final deviceModel =
      (data['model'] as String?) ?? (data['utsname']?.toString());
  final manufacturer = data['manufacturer'] as String?;

  return mobileResourceAttributesFrom(
    osName: osName,
    osVersion: osVersion,
    deviceModelIdentifier: deviceModel,
    deviceManufacturer: manufacturer,
    serviceVersion: packageInfo.version,
  );
}
```

> The async wrapper depends on platform channels and is verified via the example app / staging (see Plano de verificação), not unit tests. The **pure** `mobileResourceAttributesFrom` is unit-tested below.

- [ ] **Step 9: Add dependencies**

In `packages/comon_otel_flutter/pubspec.yaml`, add under `dependencies:` (after the `comon_otel` entry):

```yaml
  device_info_plus: ^11.0.0
  package_info_plus: ^8.0.0
```

Run: `cd packages/comon_otel_flutter && flutter pub get`
Expected: resolves successfully. (If the workspace pins different major versions elsewhere, match the pinned majors and note the chosen versions in the commit.)

- [ ] **Step 10: Export the helper**

In `packages/comon_otel_flutter/lib/comon_otel_flutter.dart`, add:

```dart
export 'src/resource/mobile_resource_detector.dart';
```

- [ ] **Step 11: Write + run the pure-mapping test**

Add inside `main()` in `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`:

```dart
test('mobileResourceAttributesFrom builds OTel resource attributes', () {
  final attributes = mobileResourceAttributesFrom(
    osName: 'iOS',
    osVersion: '17.4',
    deviceModelIdentifier: 'iPhone15,2',
    deviceManufacturer: 'Apple',
    serviceVersion: '2.0.1',
  );

  expect(attributes['os.name'], 'iOS');
  expect(attributes['os.version'], '17.4');
  expect(attributes['device.model.identifier'], 'iPhone15,2');
  expect(attributes['device.manufacturer'], 'Apple');
  expect(attributes['service.version'], '2.0.1');
  expect(attributes.containsKey('host.name'), isFalse);
});
```

Run: `cd packages/comon_otel_flutter && flutter test --plain-name "mobileResourceAttributesFrom builds OTel resource attributes"`
Expected: PASS.

- [ ] **Step 12: Document the mobile resource contract**

In `packages/comon_otel_flutter/README.md`, add a "Resource & PII" note:

```markdown
## Resource & PII on mobile

`host.name` is the device host name (e.g. "iPhone de João") — PII. On
mobile, omit `HostResourceDetector` and supply device attributes instead:

    final resourceAttributes = await detectMobileResourceAttributes();
    await Otel.init(
      serviceName: 'my-app',
      serviceVersion: resourceAttributes['service.version'] as String?,
      resourceAttributes: resourceAttributes,
      resourceDetectors: const <ResourceDetector>[
        ProcessResourceDetector(),
        TelemetrySdkResourceDetector(),
      ],
      // ...
    );
```

- [ ] **Step 13: Run both suites + analyzers**

Run: `cd packages/comon_otel && dart test test/comon_otel_test.dart`
Run: `cd packages/comon_otel_flutter && flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 14: Commit**

```bash
git add packages/comon_otel/lib/src/core/resource.dart \
        packages/comon_otel/lib/src/core/otel.dart \
        packages/comon_otel/lib/src/core/core.dart \
        packages/comon_otel/test/src/config_resource_tests.dart \
        packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart \
        packages/comon_otel_flutter/lib/comon_otel_flutter.dart \
        packages/comon_otel_flutter/pubspec.yaml \
        packages/comon_otel_flutter/test/comon_otel_flutter_test.dart \
        packages/comon_otel_flutter/README.md
git commit -F - <<'EOF'
feat(resource): add serviceVersion, telemetry.sdk.*, drop host.name PII (F2.1)

Expose serviceVersion + resourceDetectors on Otel.init so mobile can omit
HostResourceDetector (host.name is PII). Add TelemetrySdkResourceDetector
and a mobile device-attributes helper in the Flutter package.
EOF
```

---

## Verification Plan (end-to-end, after all tasks)

Unit tests are necessary but not sufficient. Verify empirically:

1. **Demo stack (in-repo):** `demo/otel_end_to_end/docker-compose.yml` (collector + Jaeger + instrumented backend). Run the Flutter example against the local collector and confirm a request produces a trace that **stitches mobile → backend** (W3C, already working) and that the HTTP span carries `screen.name` (B4b).
2. **Resilience (already covered by Tasks 1, 3, 5 tests):** chain recovery (B1), request survives instrumentation throw (B5), flush on background (B2).
3. **Against the company collector (staging):** confirm (a) OTLP/HTTP JSON accepted on `/otel/http` with TLS + auth headers; (b) attributes arrive with the contract names (`http.request.method`, `http.response.status_code`, `token-info.company.name`); (c) **no** `http.route` from the client reaches spanmetrics (B6); (d) no `host.name` in the resource (F2.1).
4. **Metrics & logs correctness (regression checks from the spec §7):** `AlwaysOnSampler` default retained (do not set a head sampler on the client); metric temporality stays cumulative; logs emitted inside a span carry `trace_id`/`span_id`.

---

## Self-Review

**Spec coverage (Fase 1 + F2.1):**
- B1 → Task 1 ✓ | B2 → Task 5 ✓ | B3 → Task 2 ✓ | B4 → Tasks 6 (umbrella + sanitize) + 7 (correlation) ✓ | B5 → Task 3 ✓ | B6 → Task 4 ✓ | F2.1 → Task 8 ✓
- Deferred (stated): F2.2–F2.7, Phase 3 roadmap, SDK error-reporting hook (the `_reportError` the spec's B1 snippet referenced — replaced here with a documented swallow).

**Type/name consistency:** `OtelFlutterScreenSpanProcessor` (Task 7) used consistently; `TelemetrySdkResourceDetector` / `ProcessResourceDetector` / `ResourceDetector` names match `resource.dart`; `mobileResourceAttributesFrom` (pure) vs `detectMobileResourceAttributes` (async) used consistently; `_isBackgrounding` (Task 5) and `_sanitizeRouteName` (Task 6) defined where used; `OtelConfig` field names in Task 2 match `otel_config.dart`.

**Known interaction:** Tasks 3 and 4 both edit `otel_dio_interceptor.dart`. Task 3 already omits the `http.route` line in the rewritten `_startRequestSpan`; Task 4 Step 3 is then a no-op for the code (still removes it if Task 3 wasn't applied) but its test edits (Step 1) are required regardless. Execute Task 3 before Task 4 for the cleanest diff.
