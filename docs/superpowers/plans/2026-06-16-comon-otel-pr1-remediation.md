# PR #1 Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Levar o PR #1 (`fix/mobile-readiness-blockers`) a um estado mergeável e imediatamente consumível pelo app `PrologFlutter`, fechando o bloqueador de deps e os achados reais da revisão multi-agente (3 majors + minors/nits), sem regredir os invariantes do projeto.

**Architecture:** Monorepo melos pub-workspace com 3 pacotes (`comon_otel` Dart puro, `comon_otel_dio` Dart puro, `comon_otel_flutter` Flutter). Toda correção entra **test-first** (vermelho → implementação → verde) e cai na branch `fix/mobile-readiness-blockers`.

**Tech Stack:** Dart/Flutter, pinado em Flutter 3.38.9 via fvm; testes via `test` (Dart) e `flutter_test` (Flutter); melos para orquestrar analyze/test.

**Spec-fonte:** `docs/superpowers/specs/2026-06-16-comon-otel-pr1-review-remediation.md`

---

## ⚠️ Toolchain — comandos por pacote (ler antes de rodar testes)

O wrapper `fvm` (3.2.1) **crasha** dentro de `comon_otel_dio`/`comon_otel_flutter` por causa do `resolution: workspace`. Use o binário pinado direto nesses dois. (A Task 9/m3 torna isso portável no `CLAUDE.md`, mas estes comandos são para esta máquina.)

| Alvo | Comando | Onde rodar |
|---|---|---|
| Bootstrap | `fvm dart pub get && fvm dart run melos bootstrap` | raiz |
| core (test) | `fvm dart test test/comon_otel_test.dart` | `packages/comon_otel` |
| dio (test) | `/Users/usuario/fvm/versions/3.38.9/bin/dart test` | `packages/comon_otel_dio` |
| flutter (test) | `/Users/usuario/fvm/versions/3.38.9/bin/flutter test` | `packages/comon_otel_flutter` |
| flutter (analyze) | `/Users/usuario/fvm/versions/3.38.9/bin/flutter analyze` | `packages/comon_otel_flutter` |
| canônico (CI) | `fvm dart run melos run analyze` · `fvm dart run melos run test` | raiz |

---

## File Structure

| Arquivo | Tarefa | Responsabilidade |
|---|---|---|
| `packages/comon_otel_flutter/pubspec.yaml` | B0 | bump dos majors de deps (`^12`/`^9`) |
| `packages/comon_otel/lib/src/core/resource.dart` | A1 | incluir `TelemetrySdkResourceDetector` nos detectores default |
| `packages/comon_otel/test/src/config_resource_tests.dart` | A1, m2 | testes de recurso default + builder B3 |
| `packages/comon_otel_flutter/lib/src/navigation/otel_navigator_observer.dart` | A2 | sanitizador endurecido (query/fragment/relativo) |
| `packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart` | A3, n3 | seam testável da extração iOS + comentário condicional |
| `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart` | A2, A3 | testes do sanitizador e da guarda de PII |
| `packages/comon_otel_dio/README.md` | m1 | corrigir exemplo de cardinalidade + tabela |
| `packages/comon_otel/lib/src/trace/batch_span_processor.dart` | n1 | try/catch no teardown |
| `packages/comon_otel/lib/src/logs/batch_log_processor.dart` | n1 | try/catch no teardown |
| `CLAUDE.md` | m3 | caminhos portáveis no guia de testes |

---

## Task 0: B0 — dobrar o bump de deps na branch do PR (bloqueador)

**Files:**
- Modify: `packages/comon_otel_flutter/pubspec.yaml`

- [ ] **Step 1: Conferir a branch atual e o estado**

Run: `git branch --show-current && git status --short`
Expected: idealmente `fix/mobile-readiness-blockers` limpo. Se estiver em `chore/bump-mobile-deps-for-app`, é o head do PR + o commit do bump — siga o Step 2 para consolidar na branch do PR.

- [ ] **Step 2: Trazer o commit do bump para a branch do PR**

```bash
git checkout fix/mobile-readiness-blockers
git cherry-pick 5753c83
```
Expected: cherry-pick limpo (o commit só toca `packages/comon_otel_flutter/pubspec.yaml`). Se já estiver aplicado, pule.

- [ ] **Step 2.5: Commitar a spec + este plano na branch do PR**

A spec (`docs/superpowers/specs/2026-06-16-comon-otel-pr1-review-remediation.md`) e este plano (`docs/superpowers/plans/2026-06-16-comon-otel-pr1-remediation.md`) foram escritos como untracked na working tree e sobrevivem ao `git checkout`, mas nada os commita — sem este passo o PR não carrega a spec/plano.

```bash
git add docs/superpowers/specs/2026-06-16-comon-otel-pr1-review-remediation.md docs/superpowers/plans/2026-06-16-comon-otel-pr1-remediation.md
git commit -m "docs: add PR #1 review remediation spec + plan"
```
Run: `git log --oneline -1 && git branch --show-current`
Expected: o commit acima no topo de `fix/mobile-readiness-blockers`.

- [ ] **Step 3: Confirmar os majors no pubspec**

Run: `grep -nE "device_info_plus|package_info_plus" packages/comon_otel_flutter/pubspec.yaml`
Expected:
```
  device_info_plus: ^12.0.0
  package_info_plus: ^9.0.0
```

- [ ] **Step 4: Re-bootstrap a partir da raiz**

Run: `fvm dart pub get && fvm dart run melos bootstrap`
Expected: `Got dependencies!` + `3 packages bootstrapped`; resolve `device_info_plus 12.x` / `package_info_plus 9.x`.

- [ ] **Step 5: Verde de fumaça (analyze)**

Run: `fvm dart run melos run analyze`
Expected: `No issues found!` nos 3 pacotes.

- [ ] **Step 6: Atualizar a nota de deps no corpo do PR**

Run: `gh pr edit 1 --repo gbtb16/comon_opentelemetry` (ou via web) — trocar "`device_info_plus ^11` + `package_info_plus ^8`" por "`^12` / `^9`".
(Sem mudança de arquivo; é metadado do PR.)

- [ ] **Step 7: Commit (se o cherry-pick não tiver criado o commit)**

Se o Step 2 já criou o commit via cherry-pick, não há o que commitar aqui. Caso tenha editado o pubspec manualmente:
```bash
git add packages/comon_otel_flutter/pubspec.yaml
git commit -m "chore(flutter): bump device_info_plus ^12 / package_info_plus ^9 to match app"
```

---

## Task 1: P0 — verificar e habilitar o CI no fork (sem código)

**Files:** nenhum (configuração de repositório).

- [ ] **Step 1: Checar o estado do Actions no fork**

Run: `gh api repos/gbtb16/comon_opentelemetry/actions/permissions`
Expected: JSON com `"enabled": true/false`. Se `false` ou se `gh pr checks 1 --repo gbtb16/comon_opentelemetry` segue "no checks reported", o Actions está desligado.

- [ ] **Step 2: Habilitar (se desligado)**

No GitHub: Settings → Actions → General → "Allow all actions". (Forks vêm com Actions desabilitado por padrão.) Alternativa CLI:
Run: `gh api -X PUT repos/gbtb16/comon_opentelemetry/actions/permissions -f enabled=true -f allowed_actions=all`

- [ ] **Step 3: Disparar/confirmar o run no PR**

Run: `git commit --allow-empty -m "ci: trigger validation run" && git push` (ou aguardar o próximo push das tasks seguintes)
Expected: `gh pr checks 1 --repo gbtb16/comon_opentelemetry` passa a listar o job `validate` (analyze + format + test em Flutter 3.38.9).

> Não-bloqueador de código, mas gate de processo: a partir daqui a validação do PR é independente, não auto-reportada.

---

## Task 2: A2 — endurecer o sanitizador de rota (major)

**Files:**
- Modify: `packages/comon_otel_flutter/lib/src/navigation/otel_navigator_observer.dart:199-221`
- Test: `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`

- [ ] **Step 1: Escrever os testes que falham**

Adicione no fim do `main()` em `comon_otel_flutter_test.dart` (antes do `}` final):

```dart
  group('OtelNavigatorObserver.sanitizeRouteName', () {
    test('collapses numeric and uuid segments to :id', () {
      expect(
        OtelNavigatorObserver.sanitizeRouteName('/order/12345'),
        '/order/:id',
      );
      expect(
        OtelNavigatorObserver.sanitizeRouteName(
          '/u/3fa85f64-5717-4562-b3fc-2c963f66afa6',
        ),
        '/u/:id',
      );
    });

    test('strips query string and fragment before sanitizing', () {
      expect(
        OtelNavigatorObserver.sanitizeRouteName('/order/12345?from=push'),
        '/order/:id',
      );
      expect(
        OtelNavigatorObserver.sanitizeRouteName('/order/12345#section'),
        '/order/:id',
      );
    });

    test('sanitizes relative names without a leading slash', () {
      expect(
        OtelNavigatorObserver.sanitizeRouteName('profile/42'),
        'profile/:id',
      );
    });
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run (em `packages/comon_otel_flutter`): `/Users/usuario/fvm/versions/3.38.9/bin/flutter test --plain-name "OtelNavigatorObserver.sanitizeRouteName"`
Expected: o caso "collapses numeric and uuid" passa; "strips query string and fragment" e "sanitizes relative names" **FALHAM** (e o método estático nem existe ainda → erro de compilação primeiro). Se for erro de compilação, é esperado — siga para o Step 3.

- [ ] **Step 3: Expor o sanitizador como seam testável e endurecê-lo**

Em `otel_navigator_observer.dart`, troque `_routeName` e `_sanitizeRouteName` (linhas 199-221) por:

```dart
  String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      return sanitizeRouteName(name);
    }
    return route.runtimeType.toString();
  }

  /// Collapses dynamic route segments to `:id` for cardinality safety.
  ///
  /// Strips any query string / fragment first and normalizes regardless of a
  /// leading `/`, so an id hidden behind `?`/`#` (e.g. `/order/12345?from=push`)
  /// or in a relative name (e.g. `profile/42` from go_router / onGenerateRoute)
  /// can't leak a high-cardinality value into span/route attributes.
  @visibleForTesting
  static String sanitizeRouteName(String name) {
    final path = name.split('?').first.split('#').first;
    final segments = path.split('/').map((segment) {
      if (segment.isEmpty) {
        return segment;
      }
      if (_numericSegment.hasMatch(segment) ||
          _uuidSegment.hasMatch(segment)) {
        return ':id';
      }
      return segment;
    });
    return segments.join('/');
  }
```

(`@visibleForTesting` já está disponível via o `import 'package:flutter/widgets.dart'` existente, que re-exporta `package:meta`.)

- [ ] **Step 4: Rodar e ver passar**

Run (em `packages/comon_otel_flutter`): `/Users/usuario/fvm/versions/3.38.9/bin/flutter test --plain-name "OtelNavigatorObserver.sanitizeRouteName"`
Expected: 3 testes PASS.

- [ ] **Step 5: Suíte flutter completa + analyze (não regredir o teste de navegação existente)**

Run: `/Users/usuario/fvm/versions/3.38.9/bin/flutter test`
Expected: All tests passed (o teste `navigation emits only a sanitized screen_ready span` continua verde).
Run: `/Users/usuario/fvm/versions/3.38.9/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/comon_otel_flutter/lib/src/navigation/otel_navigator_observer.dart packages/comon_otel_flutter/test/comon_otel_flutter_test.dart
git commit -m "fix(flutter): harden route sanitizer against query/fragment/relative names (A2)"
```

---

## Task 3: A1 — `telemetry.sdk.*` presente no recurso default (major)

**Files:**
- Modify: `packages/comon_otel/lib/src/core/resource.dart:59-63`
- Test: `packages/comon_otel/test/src/config_resource_tests.dart`

> **Decisão (deferida na spec):** este plano implementa a **Opção A** — adicionar `TelemetrySdkResourceDetector` aos `defaultDetectors`. Respeita o contrato "listas de detector substituem" firmado no commit `2e0ae62`, e o exemplo mobile do README já lista o detector explicitamente (linhas 130-132), então o caminho mobile não regride. Se a revisão preferir a Opção B (merge garantido, indropável), trocar este passo por um always-merge em `Resource.autoDetect` — mas isso abre exceção deliberada ao contrato de substituição.

- [ ] **Step 1: Escrever o teste que falha**

Adicione dentro do `group('config and resources', () {` em `config_resource_tests.dart` (após o teste "init exposes batch and metric-reader configuration explicitly", ~linha 245):

```dart
    test('default resource carries spec-mandatory telemetry.sdk attributes', () async {
      await Otel.shutdown();
      await Otel.init(serviceName: 'sdk-default-service');

      final attributes = Otel.instance.tracerProvider.resource.attributes;
      expect(attributes['telemetry.sdk.name'], 'comon_otel');
      expect(attributes['telemetry.sdk.language'], 'dart');
      expect(attributes['telemetry.sdk.version'], isNotEmpty);
    });
```

- [ ] **Step 2: Rodar e ver falhar**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart --plain-name "default resource carries spec-mandatory telemetry.sdk attributes"`
Expected: FAIL — `telemetry.sdk.name` é `null` (detector não está nos defaults).

- [ ] **Step 3: Adicionar o detector aos defaults**

Em `resource.dart`, troque a lista `defaultDetectors` (linhas 60-63) por:

```dart
  /// Default detectors used by [autoDetect].
  static const List<ResourceDetector> defaultDetectors = <ResourceDetector>[
    ProcessResourceDetector(),
    HostResourceDetector(),
    TelemetrySdkResourceDetector(),
  ];
```

- [ ] **Step 4: Rodar e ver passar**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart --plain-name "default resource carries spec-mandatory telemetry.sdk attributes"`
Expected: PASS.

- [ ] **Step 5: Suíte core completa**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart`
Expected: All tests passed. Se algum teste existente assertar um **conjunto exato** de atributos de recurso (improvável — `HostResourceDetector` já torna o mapa não-mínimo), atualize-o para incluir `telemetry.sdk.*`; isso é mudança esperada-e-tratada, não surpresa.

- [ ] **Step 6: Commit**

```bash
git add packages/comon_otel/lib/src/core/resource.dart packages/comon_otel/test/src/config_resource_tests.dart
git commit -m "fix(resource): emit spec-mandatory telemetry.sdk.* by default (A1)"
```

---

## Task 4: A3 — guarda de PII iOS testável + teste de regressão (major)

**Files:**
- Modify: `packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart`
- Test: `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`

- [ ] **Step 1: Escrever o teste que falha**

No topo de `comon_otel_flutter_test.dart`, garanta o import (após os imports existentes):

```dart
import 'package:device_info_plus/device_info_plus.dart';
```

Adicione o teste dentro do `main()`:

```dart
  test('iosResourceValuesFrom reads systemName, never the PII device name', () {
    const piiDeviceName = 'iPhone de João';
    final ios = IosDeviceInfo.setMockInitialValues(
      name: piiDeviceName, // PII — must NOT appear in any extracted value
      systemName: 'iOS',
      systemVersion: '17.4',
      model: 'iPhone',
      modelName: 'iPhone 15 Pro',
      localizedModel: 'iPhone',
      identifierForVendor: 'FAKE-UUID',
      isPhysicalDevice: true,
      isiOSAppOnMac: false,
      isiOSAppOnVision: false,
      freeDiskSize: 1,
      totalDiskSize: 2,
      physicalRamSize: 1,
      availableRamSize: 1,
      utsname: IosUtsname.setMockInitialValues(
        sysname: 'Darwin',
        nodename: 'iPhone',
        release: '23.0.0',
        version: 'x',
        machine: 'iPhone15,2',
      ),
    );

    final values = iosResourceValuesFrom(ios);

    expect(values.osName, 'iOS');
    expect(values.osVersion, '17.4');
    expect(values.modelId, 'iPhone15,2');
    expect(values.manufacturer, 'Apple');
    expect(
      <String>[
        values.osName,
        values.osVersion,
        values.modelId,
        values.manufacturer,
      ],
      isNot(contains(piiDeviceName)),
    );
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run (em `packages/comon_otel_flutter`): `/Users/usuario/fvm/versions/3.38.9/bin/flutter test --plain-name "iosResourceValuesFrom reads systemName"`
Expected: erro de compilação (`iosResourceValuesFrom` não existe). Esperado — siga para o Step 3.

- [ ] **Step 3: Extrair o seam testável da extração iOS**

Em `mobile_resource_detector.dart`, adicione o import no topo (após `import 'package:package_info_plus/package_info_plus.dart';`):

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

Adicione a função pura (antes de `detectMobileResourceAttributes`):

```dart
/// Non-PII resource values extracted from iOS device info.
///
/// Reads [IosDeviceInfo.systemName] ("iOS"/"iPadOS") — deliberately NOT
/// [IosDeviceInfo.name], the user-assigned device name ("iPhone de João") that
/// would re-introduce the host.name PII this package omits on mobile. Kept as a
/// named seam so a regression (reading `name`) is caught by a unit test.
@visibleForTesting
({String osName, String osVersion, String modelId, String manufacturer})
iosResourceValuesFrom(IosDeviceInfo ios) {
  return (
    osName: ios.systemName,
    osVersion: ios.systemVersion,
    modelId: ios.utsname.machine,
    manufacturer: 'Apple',
  );
}
```

Troque o ramo iOS dentro de `detectMobileResourceAttributes` (linhas 46-51) por:

```dart
  if (Platform.isIOS) {
    final ios = await deviceInfo.iosInfo;
    final values = iosResourceValuesFrom(ios);
    osName = values.osName;
    osVersion = values.osVersion;
    deviceModelIdentifier = values.modelId;
    deviceManufacturer = values.manufacturer;
  } else if (Platform.isAndroid) {
```

- [ ] **Step 4: Rodar e ver passar**

Run (em `packages/comon_otel_flutter`): `/Users/usuario/fvm/versions/3.38.9/bin/flutter test --plain-name "iosResourceValuesFrom reads systemName"`
Expected: PASS. (Trocar `ios.systemName` por `ios.name` em `iosResourceValuesFrom` faz o teste FALHAR — é o objetivo.)

- [ ] **Step 5: Suíte flutter completa + analyze**

Run: `/Users/usuario/fvm/versions/3.38.9/bin/flutter test`
Expected: All tests passed.
Run: `/Users/usuario/fvm/versions/3.38.9/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart packages/comon_otel_flutter/test/comon_otel_flutter_test.dart
git commit -m "test+refactor(flutter): pin iOS PII guard (systemName, not name) with a unit test (A3)"
```

---

## Task 5: m1 — corrigir os exemplos do README do dio (minor)

**Files:**
- Modify: `packages/comon_otel_dio/README.md:62` e `:78`

- [ ] **Step 1: Trocar o exemplo de `spanNameBuilder` (linha 62)**

Substitua:
```dart
      spanNameBuilder: (options) => 'api ${options.method} ${options.uri.path}',
```
por:
```dart
      // Keep span names low-cardinality: never bake a raw, unsanitized path
      // (e.g. "/order/12345") into the name — that explodes spanmetrics in the
      // collector. Use the method, or a sanitized/templated route only.
      spanNameBuilder: (options) => 'api ${options.method}',
```

- [ ] **Step 2: Remover a linha `http.route` da tabela (linha 78)**

Apague a linha:
```
| `http.route` | every request |
```
(O interceptor não seta `http.route` — o B6 removeu, e o teste `comon_otel_dio_test.dart` asserta a ausência. A linha contradiz o código.)

- [ ] **Step 3: Verificar coerência doc-vs-código**

Run (em `packages/comon_otel_dio`): `grep -rn "httpRoute\|http.route" lib`
Expected: nenhum hit em `lib/` (confirma que a tabela não deve listar `http.route`).

- [ ] **Step 4: Commit**

```bash
git add packages/comon_otel_dio/README.md
git commit -m "docs(dio): drop http.route row and de-footgun the spanNameBuilder example (m1)"
```

---

## Task 6: m2 — teste de que os flags B3 produzem batch/periodic (minor)

**Files:**
- Test: `packages/comon_otel/test/src/config_resource_tests.dart`

> O teste de batch existente (`uses batch processors ... when env config requests them`, ~linha 145) dirige o batching por **env**. Este teste fecha o gap dirigindo pelos **params explícitos** do `Otel.init` (B3), usando o mesmo harness de transporte fake (`_FakeOtlpHttpTransport`).

- [ ] **Step 1: Escrever o teste que falha (comportamental)**

Adicione dentro do `group('config and resources', () {`:

```dart
    test(
      'explicit batch/periodic init params drive batch behavior (no env)',
      () async {
        final transport = _FakeOtlpHttpTransport();

        await Otel.shutdown();
        await Otel.init(
          serviceName: 'explicit-batch-service',
          exporter: OtelExporter.otlpHttpJson,
          endpoint: 'https://explicit-batch.example.com',
          otlpTransport: transport,
          useBatchSpanProcessor: true,
          batchSpanProcessorScheduleDelay: const Duration(seconds: 60),
          batchSpanProcessorMaxExportBatchSize: 512,
          useBatchLogProcessor: true,
          batchLogProcessorScheduleDelay: const Duration(seconds: 60),
        );

        await Otel.instance.tracer.traceAsync(
          'explicit-batch-span',
          fn: () async {
            Otel.instance.logger.info('explicit-batch-log');
          },
        );

        // With a 60s schedule delay and batching ON, nothing is exported yet.
        expect(transport.requests, isEmpty);

        await Otel.forceFlush();

        // The http/json exporter has async beyond the flush-chain await, so
        // poll until the trace request lands (mirrors the existing
        // "reads OTEL env config" test, ~lines 119-123).
        while (transport.requests.where((request) {
          return request.request.body.contains('resourceSpans');
        }).isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }

        final traceRequests = transport.requests.where((request) {
          return request.request.body.contains('resourceSpans');
        }).length;
        expect(traceRequests, greaterThanOrEqualTo(1));
      },
    );
```

- [ ] **Step 2: Rodar e ver passar (já que os builders leem os flags)**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart --plain-name "explicit batch/periodic init params drive batch behavior"`
Expected: PASS. Se FALHAR (export antes do flush), é regressão real no builder — investigar `_buildSpanProcessors` em `otel.dart`.

> Este teste é uma rede de regressão: se um futuro refactor fizer os flags pararem de produzir `BatchSpanProcessor`, a asserção `transport.requests isEmpty` quebra.

- [ ] **Step 3: Suíte core completa**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart`
Expected: All tests passed.

- [ ] **Step 4: Commit**

```bash
git add packages/comon_otel/test/src/config_resource_tests.dart
git commit -m "test(core): assert explicit B3 flags drive batch behavior (m2)"
```

---

## Task 7: n1 — try/catch no teardown de `forceFlush()`/`shutdown()` (nit)

**Files:**
- Modify: `packages/comon_otel/lib/src/trace/batch_span_processor.dart:52-67`
- Modify: `packages/comon_otel/lib/src/logs/batch_log_processor.dart` (métodos `forceFlush`/`shutdown` análogos)

> Decisão da spec: **fazer** (completude do invariante "telemetria nunca estoura no host"). `_flushBatch` já é throw-safe; falta o `await _exporter.forceFlush()/shutdown()` final.

- [ ] **Step 1: Escrever o teste que falha (span processor)**

`signals_pipeline_tests.dart` é um `part of '../comon_otel_test.dart'` com `void defineSignalsPipelineTests() { group('signals and pipeline', () { ... } }`. Adicione o teste **dentro de `group('signals and pipeline', ...)`** — um exporter que estoura no teardown (os tipos `SpanExporter`/`ExportResult`/`SpanData`/`BatchSpanProcessor` já vêm da library do `part`, sem novos imports):

```dart
    test('BatchSpanProcessor.forceFlush swallows a throwing exporter teardown', () async {
      final exporter = _ThrowingTeardownSpanExporter();
      final processor = BatchSpanProcessor(exporter: exporter);

      // Must complete normally even though the exporter throws on forceFlush.
      await processor.forceFlush();
      await processor.shutdown();

      expect(exporter.forceFlushCalled, isTrue);
      expect(exporter.shutdownCalled, isTrue);
    });
```

E declare o fake como **top-level no part file** (fora da função `defineSignalsPipelineTests`, no nível do arquivo — Dart permite declarações top-level em `part`):

```dart
final class _ThrowingTeardownSpanExporter implements SpanExporter {
  bool forceFlushCalled = false;
  bool shutdownCalled = false;

  @override
  Future<ExportResult> export(List<SpanData> data) async => ExportResult.success;

  @override
  Future<void> forceFlush() async {
    forceFlushCalled = true;
    throw StateError('teardown boom');
  }

  @override
  Future<void> shutdown() async {
    shutdownCalled = true;
    throw StateError('shutdown boom');
  }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart --plain-name "BatchSpanProcessor.forceFlush swallows a throwing exporter teardown"`
Expected: FAIL — a exceção do exporter re-propaga (o `await processor.forceFlush()` lança).

- [ ] **Step 3: Envolver o teardown em try/catch (span processor)**

Em `batch_span_processor.dart`, troque `forceFlush`/`shutdown` (linhas 52-67) por:

```dart
  @override
  Future<void> forceFlush() async {
    await _flushBatch(all: true);
    try {
      await _exporter.forceFlush();
    } catch (_) {
      // Telemetry teardown must never throw into the host. SDK-level error
      // reporting is tracked separately (F2.2, out of scope here).
    }
  }

  @override
  Future<void> shutdown() async {
    if (_isShutdown) {
      return;
    }
    _isShutdown = true;
    _timer?.cancel();
    await _flushBatch(all: true);
    try {
      await _exporter.shutdown();
    } catch (_) {
      // See forceFlush: teardown failures are swallowed by design.
    }
  }
```

- [ ] **Step 4: Aplicar o mesmo padrão no log processor**

Em `batch_log_processor.dart`, envolva os `await _exporter.forceFlush();` e `await _exporter.shutdown();` finais nos mesmos blocos `try { ... } catch (_) { /* teardown ... */ }` (espelhando o span processor).

- [ ] **Step 5: Rodar e ver passar**

Run (em `packages/comon_otel`): `fvm dart test test/comon_otel_test.dart`
Expected: All tests passed (incluindo o novo).

- [ ] **Step 6: Commit**

```bash
git add packages/comon_otel/lib/src/trace/batch_span_processor.dart packages/comon_otel/lib/src/logs/batch_log_processor.dart packages/comon_otel/test/src/signals_pipeline_tests.dart
git commit -m "fix(core): swallow exporter teardown failures in forceFlush/shutdown (n1)"
```

---

## Task 8: n3 — comentar que `service.version` é runtime-condicional (nit)

**Files:**
- Modify: `packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart:24-25`

- [ ] **Step 1: Adicionar o comentário**

Em `mobileResourceAttributesFrom`, antes da linha `if (serviceVersion != null && serviceVersion.isNotEmpty)`:

```dart
    // service.version is conditional: emitted only when a non-empty version is
    // resolved. On a built app PackageInfo.version is always present; in tests
    // or unusual hosts it may be empty, in which case the attribute is omitted.
    if (serviceVersion != null && serviceVersion.isNotEmpty)
      'service.version': serviceVersion,
```

- [ ] **Step 2: Analyze (sem mudança de comportamento)**

Run (em `packages/comon_otel_flutter`): `/Users/usuario/fvm/versions/3.38.9/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add packages/comon_otel_flutter/lib/src/resource/mobile_resource_detector.dart
git commit -m "docs(flutter): note service.version is runtime-conditional (n3)"
```

---

## Task 9: m3 — caminhos portáveis no `CLAUDE.md` (minor)

**Files:**
- Modify: `CLAUDE.md` (seção Toolchain, ~linhas 30-32)

- [ ] **Step 1: Confirmar a localização do binário pinado de forma portável**

Run: `fvm flutter --version >/dev/null 2>&1; ls "$HOME/fvm/versions/3.38.9/bin/flutter"`
Expected: o caminho existe sob `$HOME` (não hardcoded em `/Users/usuario`).

- [ ] **Step 2: Trocar os caminhos absolutos por `$HOME`**

Em `CLAUDE.md`, substitua o bloco de comandos que usa `/Users/usuario/fvm/versions/3.38.9/bin/...` por:

```bash
  "$HOME/fvm/versions/3.38.9/bin/dart" test       # comon_otel_dio
  "$HOME/fvm/versions/3.38.9/bin/flutter" test    # comon_otel_flutter
  "$HOME/fvm/versions/3.38.9/bin/flutter" analyze # comon_otel_flutter
```

Mantenha a explicação do bug do wrapper fvm 3.2.1 logo acima.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: use \$HOME instead of a machine-specific fvm path in test guidance (m3)"
```

---

## Task 10: n2 + n4 — registrar no-action e reconciliar contagens (nits)

**Files:**
- Modify: `CLAUDE.md` ("Totais de referência") e corpo do PR.

- [ ] **Step 1: n2 — registrar a decisão de não-ação**

O enqueue em `onEnd`/`onEmit` (`batch_span_processor.dart:36-49`, `batch_log_processor.dart`) fora de try/catch é **pré-existente** (byte-idêntico ao `main`) e o throw é praticamente impossível (`toSpanData()` em span já gravado). Decisão: **não mexer** nesta task. Já está documentado na spec §5.10 — nenhuma mudança de código aqui.

- [ ] **Step 2: n4 — rodar a suíte canônica e capturar os totais reais**

Run (na raiz): `fvm dart run melos run test`
Expected: ver as três linhas `All tests passed!` com os contadores `+N` de core, dio e flutter. Anote os três números.

- [ ] **Step 3: Atualizar "Totais de referência" no `CLAUDE.md`**

Substitua a linha `**Totais de referência (HEAD da branch de mobile-readiness):** core 92 · dio 13 · flutter 23 · analyze limpo.` pelos números reais capturados no Step 2 (ex.: `core <N> · dio 13 · flutter <N> · analyze limpo`).

- [ ] **Step 4: Atualizar o corpo do PR (Validation)**

Run: `gh pr edit 1 --repo gbtb16/comon_opentelemetry` — alinhar a contagem de testes da seção Validation com os números reais do Step 2.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: reconcile test counts with the canonical suite (n4)"
```

---

## Task 11: Verificação final + gates de go-live + preparar merge

**Files:** nenhum (verificação).

- [ ] **Step 1: Suíte canônica completa (o que o CI roda)**

Run (na raiz):
```bash
fvm dart run melos run analyze
fvm dart run melos exec --fail-fast -- "dart format --set-exit-if-changed ."
fvm dart run melos run test
```
Expected: analyze limpo · format sem diffs · três `All tests passed!`. Se `dart format` acusar diffs, rode `fvm dart run melos exec -- "dart format ."`, revise e commite (`style: dart format`).

- [ ] **Step 2: Push e confirmar o CI verde (depende da Task 1)**

```bash
git push
```
Run: `gh pr checks 1 --repo gbtb16/comon_opentelemetry`
Expected: job `validate` verde (não mais "no checks reported").

- [ ] **Step 3: Registrar os gates de go-live pendentes (não-bloqueadores de merge)**

Confirme que a spec `2026-06-16-comon-otel-pr1-review-remediation.md` §7 lista os gates empíricos (device real iOS/Android para PII; stitch mobile→backend; collector de staging; regressões da §7 da design spec). Estes ficam como follow-up de go-live, **não** bloqueiam o merge do PR no `main` do fork. Decida com o usuário se viram issues/tickets.

- [ ] **Step 4: Confirmar mergeabilidade**

Run: `gh pr view 1 --repo gbtb16/comon_opentelemetry --json mergeable,mergeStateStatus,changedFiles`
Expected: `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`.

- [ ] **Step 5: Handoff para o merge**

Reportar ao usuário: B0 fechado (deps `^12`/`^9`), 3 majors corrigidos com teste, minors/nits resolvidos, suíte verde + CI verde. PR pronto para merge no `main`. Oferecer mover o ticket no Jira se houver `PL-XXXX` no nome da branch (não há neste caso — `fix/mobile-readiness-blockers`).

---

## Self-Review (cobertura da spec)

- **B0** → Task 0 ✅ · **P0** → Task 1 ✅ · **A1** → Task 3 ✅ · **A2** → Task 2 ✅ · **A3** → Task 4 ✅
- **m1** → Task 5 ✅ · **m2** → Task 6 ✅ · **m3** → Task 9 ✅
- **n1** → Task 7 ✅ · **n2** → Task 10 (no-action, registrado) ✅ · **n3** → Task 8 ✅ · **n4** → Task 10 ✅
- **n5** (swallow Dio onResponse/onError) → sem ação, registrado na spec §6; nenhuma task (decisão verificada: não inventar seam).
- **Gates de go-live** (spec §7) → Task 11 Step 3.
- Consistência de tipos: `sanitizeRouteName` (Task 2) e `iosResourceValuesFrom` (Task 4) usados com a mesma assinatura nos testes; `OtelExporter.otlpHttpJson` / `_FakeOtlpHttpTransport` (Task 6) batem com o harness existente em `config_resource_tests.dart`.
