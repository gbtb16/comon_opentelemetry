# comon_otel_flutter Implementation Plan

This package is intended to provide Flutter-first instrumentation on top of `comon_otel`.

## Phase 1: Bootstrap Foundations

- [x] Create sibling Flutter package in `packages/comon_otel_flutter`
- [x] Add package dependency on local `comon_otel`
- [x] Add `ComonOtelFlutter.install(...)`
- [x] Add `OtelNavigatorObserver`
- [x] Add `OtelFlutterBindingObserver`
- [x] Add Flutter framework error capture
- [x] Add `PlatformDispatcher` error capture
- [x] Add initial tests for route, lifecycle, and error coverage

## Phase 2: App Startup And Screen Semantics

- [x] App startup span from `main()` bootstrap to first frame
- [x] First-frame marker and explicit first-interaction marker API
- [x] Screen-ready spans for page transitions
- [x] Route attributes aligned with OpenTelemetry mobile conventions where possible
- [x] Foreground/background duration metrics

## Phase 3: Performance Telemetry

- [x] Frame timing collection via `addTimingsCallback`
- [x] Jank and slow-frame metrics
- [x] App memory-pressure counters and logs
- [x] UI thread stall heuristics where Flutter surfaces enough signals

## Phase 4: Error And Crash Enrichment

- [x] Error grouping attributes
- [x] Widget tree and route context enrichment for captured errors
- [x] Breadcrumb-style log enrichment
- [x] Optional integration points for Crashlytics and Sentry coexistence

## Phase 5: Client Integrations Common In Flutter Apps

- [~] Deferred for now while work continues in phases 6, 7, and 8
- [ ] Separate Dio integration package in `packages/comon_otel_dio`
- [ ] Persistence helpers for Drift, Isar, Hive, and shared preferences patterns

## Phase 6: UX Interaction Instrumentation

- [x] Tap and gesture instrumentation helpers
- [x] Form submit and validation spans
- [ ] Background task and isolate helpers for Flutter apps
- [x] Widget-level opt-in tracing helpers for expensive flows

## Phase 7: Docs And Examples

- [x] Full example app
- [ ] Collector-backed Flutter integration test flow
- [ ] Android and iOS setup notes
- [ ] Production guidance for batching, offline behavior, and exporter selection

## Phase 8: Большой интеграционный тест/пример в корне репозитория
- [x] Простой бекенд на dart с паткетом comon_otel
- [x] Простой frontend на flutter с паткетом comon_otel_flutter
- [x] Поднимаемый в докере коллектор 
- [x] Проведение цепочки событий в приложении которая влияет на бекенд и возможность посмотреть полный трейст от мп до бека и обратно 