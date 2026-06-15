# Auditoria de Resiliência Mobile e Maturidade — comon_opentelemetry

> Escopo: fork local em `/Users/usuario/projects/anywhere/comon_opentelemetry`, adoção planejada via git dependency no HEAD (`fbf61da`). Contexto: app Flutter mobile, rede instável, app morto/suspenso pelo OS, dados podem ser PII.

## Resumo

A engenharia do core é boa: limites de fila existem, shutdown/forceFlush cancelam timers e drenam filas corretamente, retry com backoff exponencial está implementado, e os contratos de integração são totalmente implementados (não são interfaces vazias). **Porém, para o cenário mobile específico, há perdas de dados graves e silenciosas.** O achado mais severo é um bug de "envenenamento" da cadeia de flush no `BatchSpanProcessor`/`BatchLogProcessor`: um único `TimeoutException` (disparado justamente pela rede móvel lenta, via o env var padrão `OTEL_BSP_EXPORT_TIMEOUT`) deixa o pipeline de telemetria **permanentemente morto** sem qualquer sinal, recuperável apenas com re-inicialização. Soma-se a isso: nenhuma persistência offline em disco (fila em memória se perde quando o OS mata/suspende o app), nenhum flush no lifecycle `paused`/`detached`, descarte silencioso de spans no overflow da fila, e ausência de qualquer hook de scrubbing/redaction de PII em atributos de spans/logs.

---

## BLOQUEADORES

### B1. Envenenamento permanente da cadeia de flush (`_pendingFlush`) — telemetria morre silenciosamente após 1 timeout

**Evidência:** `packages/comon_otel/lib/src/trace/batch_span_processor.dart:69-94` (idêntico em `packages/comon_otel/lib/src/logs/batch_log_processor.dart:78-103`):

```dart
Future<void> _flushBatch({bool all = false}) {
  _pendingFlush = _pendingFlush.then((_) async {     // .then SEM onError
    ...
    final exportFuture = _exporter.export(batch);
    if (exportTimeout == null) {
      await exportFuture;
    } else {
      await exportFuture.timeout(exportTimeout!);    // <-- lança TimeoutException
    }
    ...
  });
  return _pendingFlush;
}
```

Em Dart, `Future.then(onValue)` sem callback `onError` **propaga o erro e pula o `onValue`**. Quando o corpo do `_flushBatch` lança (via `exportFuture.timeout(...)` na linha 87 — o caso de rede móvel lenta), `_pendingFlush` torna-se um Future permanentemente rejeitado. Em toda chamada subsequente, `_pendingFlush.then(callback)` faz curto-circuito sobre o erro obsoleto e **o callback nunca mais executa**. O `Timer.periodic` (linha 17-19) continua disparando contra uma cadeia morta; `onEnd` continua enfileirando; `maxQueueSize` continua descartando os mais antigos. **Nada mais é exportado até um `Otel.init()`/`dispose()`.**

Trigger é padrão e esperado em mobile: `exportTimeout` vem de `OTEL_BSP_EXPORT_TIMEOUT` / `OTEL_BLRP_EXPORT_TIMEOUT` (`packages/comon_otel/lib/src/core/otel_env_config.dart:139-140, 162-163`), env vars padrão do OpenTelemetry. Os exporters OTLP não lançam (retornam `ExportResult.failure`), mas o `.timeout()` lança, e qualquer exporter customizado que lance também envenena a cadeia.

**Impacto:** Crítico. Uma única lentidão de rede (corriqueira em mobile) desliga toda a telemetria de traces e logs para o resto da sessão, sem nenhum aviso. É a falha mais perigosa porque é silenciosa e permanente.

**Correção concreta:** Isolar cada flush do estado da cadeia. Capturar erros dentro do callback para que o Future encadeado **sempre resolva** com sucesso:

```dart
_pendingFlush = _pendingFlush.then((_) async {
  try {
    // ... corpo atual ...
  } catch (error, stackTrace) {
    _reportError(error, stackTrace); // ver B3 — sinalizar, não engolir
  }
});
```

(ou anexar `.catchError(...)`). Adicionar teste que injeta um exporter que lança/estoura timeout e verifica que o flush seguinte ainda exporta.

---

### B2. Zero persistência offline — fila em memória perdida quando o OS mata/suspende o app

**Evidência:** As filas são puramente em memória — `final Queue<SpanData> _queue = Queue<SpanData>();` (`batch_span_processor.dart:27`) e `final Queue<LogRecord> _queue = Queue<LogRecord>();` (`batch_log_processor.dart:36`). Busca por persistência em todo o `lib` retorna **zero** resultados de `sharedpreferences|hive|sqflite|path_provider|writeAsString|File(|isar|persist|disk|offline` (único match de `archive` é gzip de compressão em `http_transport.dart:3`).

Pior, **não há flush no lifecycle**: `packages/comon_otel_flutter/lib/src/lifecycle/otel_flutter_binding_observer.dart:97-121` (`didChangeAppLifecycleState`) só registra métricas/logs de duração e breadcrumbs — **não chama `Otel.forceFlush()`** em `paused`/`inactive`/`detached`:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  OtelFlutterBreadcrumbs.add(...);
  if (Otel.isInitialized) {
    _recordLifecycleDurations(state);
    if (logLifecycleTransitions) { Otel.instance.loggerProvider... }
  }
  _lastLifecycleState = state;        // nenhum forceFlush em background
}
```

**Impacto:** Alto (gap clássico mobile, confirmado). Com `scheduleDelay` default de 5s (spans) e 1s (logs) e fila de até 2048, tudo o que estiver na fila quando o OS suspende/mata o app — incluindo o crash que acabou de acontecer — desaparece. Em mobile, é exatamente quando os dados mais importam (crashes, ANRs) que eles se perdem.

**Correção concreta:** (a) Curto prazo — no `OtelFlutterBindingObserver`, em `paused`/`detached`, chamar `unawaited(Otel.forceFlush())` (drena para a rede enquanto o app ainda respira). (b) Médio prazo — buffer offline em disco (ex.: append-only em `path_provider`) drenado no próximo cold start; é o que SDKs mobile maduros (Sentry, Datadog RUM) fazem.

---

## ATENÇÃO (corrigir logo após adoção)

### A1. `ExportResult.failure` é descartado pelo batch processor — perda silenciosa sem sinal

**Evidência:** `batch_span_processor.dart:82-89` faz `await exportFuture` mas **nunca inspeciona o `ExportResult` retornado**. Os exporters OTLP, após esgotar o retry, retornam `ExportResult.failure` em vez de lançar (`export_retry.dart:71,110`; `http_protobuf_span_exporter.dart:36-57` retorna o resultado direto). Como o batch já fez `_queue.removeFirst()` (linha 79) antes do export, os spans são removidos da fila e o `failure` é ignorado: **drop silencioso, sem retry adicional, sem log**.

Nota de precisão: retry **existe** (`OtlpRetryConfig(maxAttempts: 3, ...)` com backoff exponencial capado em 2s — `export_retry.dart:6-26`). O problema não é ausência de retry, e sim que após o retry curto se esgotar, a falha não é sinalizada nem os dados re-enfileirados.

**Impacto:** O operador não tem como saber que a telemetria está caindo. Combinado com B1, qualquer falha de export é invisível.

**Correção:** Inspecionar o `ExportResult`; expor um callback/contador de exports falhos (ver A3) e considerar re-enfileiramento limitado.

### A2. Overflow da fila descarta o mais antigo sem contador nem log

**Evidência:** `batch_span_processor.dart:42-44` e `batch_log_processor.dart:49-51`:

```dart
if (_queue.length >= maxQueueSize) {
  _queue.removeFirst();   // descarta silenciosamente o item mais antigo
}
```

Não há `droppedCount`, nem log, nem métrica. Sob backpressure (rede caída + alto volume), dados somem sem rastro. Segundo caminho de perda silenciosa, distinto de A1.

**Impacto:** Médio-alto. Em mobile offline, a fila enche rápido e o usuário nunca sabe quantos eventos foram perdidos.

**Correção:** Manter um contador de descartes e emiti-lo periodicamente como métrica interna / log de aviso.

### A3. `catch` que engolem erros sem sinal

**Evidência:**
- `simple_span_processor.dart:27` → `.catchError((_) {})` (descarta todo erro de export)
- `simple_log_processor.dart:23` → `.catchError((_) {})` (idem)
- `export_retry.dart:55,94` → `} catch (_) {` (silencioso entre tentativas; aceitável por ser intra-retry, mas sem telemetria de diagnóstico)

**Impacto:** Médio. Com `SimpleSpanProcessor`/`SimpleLogProcessor` (o default quando não há config de batch — `otel.dart:307,349`), 100% das falhas de export são silenciosas. Não há nenhum canal de auto-diagnóstico ("o SDK não está conseguindo exportar").

**Correção:** Adicionar um hook global de erro do SDK (estilo `OpenTelemetry.errorHandler`) para que o app possa observar falhas internas.

### A4. PII / dados sensíveis vão crus — nenhum hook de scrubbing de atributos

**Evidência:** A única redaction existente é **header-only no Dio**: `packages/comon_otel_dio/lib/src/otel_dio_interceptor.dart:24,64,68,266` (`redactedHeaderValue = '[REDACTED]'`). Não há nenhum hook de redaction/scrubbing de **valores** de atributos de span ou log. O que existe em `span.dart` (`_limitAttributes`/`_sanitizeLink`, linhas 178-315) é apenas **limite de contagem/cardinalidade** (spec span limits) — não toca o conteúdo. `toSpanData()` (`span.dart:263-287`) serializa os atributos como estão. O `OtelLogExtension.handleLog` (`integrations/contracts/otel_log_extension.dart`) repassa `extra`, `error.toString()` e stacktrace crus.

**Impacto:** Médio-alto para mobile com PII. Qualquer atributo que o app (ou as integrações de DB/HTTP, ex.: `db.statement`, query strings) sete vai cru ao collector. Sem ponto central para mascarar e-mails, tokens, etc.

**Correção:** Adicionar um `SpanProcessor`/`LogProcessor` de redaction configurável (allow/deny-list de chaves + função de transformação de valores) executado antes do export.

---

## OK / PONTOS FORTES

- **Limites de fila existem e funcionam** — `maxQueueSize` default 2048, `maxBatchSize` 512 em ambos os batch processors (`batch_span_processor.dart:12-14`, `batch_log_processor.dart:13-16`). Não há crescimento ilimitado: a fila não vaza para OOM (descarta o mais antigo — ver A2).
- **Shutdown/forceFlush bem implementados e idempotentes** — `shutdown()` checa `_isShutdown`, cancela o `Timer` e drena tudo (`all: true`) antes de fechar o exporter (`batch_span_processor.dart:58-67`, `batch_log_processor.dart:66-76`, `periodic_metric_reader.dart:76-85`). `Otel.dispose()` encadeia shutdown dos três providers e limpa o singleton (`otel.dart:559-566`). `forceFlush` propaga para os três (`otel.dart:568-573`). Sem vazamento de timers no caminho de shutdown.
- **Retry com backoff** — exponencial, capado, respeita `Retry-After` (`export_retry.dart`), com classificação de códigos gRPC retryáveis (`grpc_transport.dart:120-127`).
- **Isolate: correto para o modelo de memória do Dart.** `otel_isolate.dart` serializa o contexto via `toMessage()`/`fromMessage` (linhas 114-132 / 39-78) e o usa em `Isolate.run` (linhas 148-198). Como isolates Dart **não compartilham memória**, o singleton global `Otel._instance` não sofre data race — cada isolate tem o seu. A inicialização local é detectada (`initializedHere`, linha 158) e o isolate faz seu próprio shutdown no `finally` (linha 194-196). **Limitação de design (não bug):** o contexto é capturado one-way no spawn; não há propagação de volta de spans criados dentro do isolate para o isolate pai. Documentar isso.
- **Span limits spec-compliant** — contagem de atributos/eventos/links com `droppedCount` rastreado (`span.dart`), configurável por env.
- **Instrumentação Flutter robusta** — restaura handlers de erro anteriores no `dispose` (`comon_otel_flutter_instrumentation.dart:186-204`), encadeia fallbacks (`...?? previousFlutterErrorHandler`), observa frames/stalls/startup/navegação.

---

## Maturidade

**TODOs / stubs:** `grep -rn "TODO\|FIXME\|throw UnimplementedError\|UnimplementedError"` sobre `packages/*/lib` → **0 ocorrências**. Código limpo, sem dívida marcada explicitamente nem stubs.

**Contratos de integração:** Todos **implementados, não vazios** — `integrations/contracts/`: `otel_database_mixin.dart` (tracing+metrics+logging completos de operações DB, 109 linhas), `otel_db_metrics.dart` (5 instrumentos), `slow_query_detector.dart` (funcional), `otel_log_extension.dart` (bridge completo). Apenas `OtelLogBridge` (`otel_log_bridge.dart`) é uma interface pura — apropriado, é o contrato base.

**Cobertura de testes:** ~4.700 linhas de teste, mas **concentradas no core e na pipeline OTLP**:
- Bem cobertos: config/resource (1.198 linhas), trace core (1.002), propagação (370), pipeline de signals (368), integração com collector OTLP / retry / roundtrip (~440), transporte HTTP (72).
- **Lacunas críticas de teste:**
  - `comon_otel_flutter` → **1 arquivo** (`comon_otel_flutter_test.dart`). Lifecycle observer, error hooks, frame timing, startup tracker, navigation — praticamente sem cobertura. Justamente a camada mobile mais sensível.
  - `comon_otel_dio` → **1 arquivo** (`comon_otel_dio_test.dart`).
  - **B1 (chain poisoning), B2 (perda no lifecycle), A1 (drop em failure) e A2 (drop em overflow) não têm teste** — são exatamente os caminhos de resiliência que faltam. A ausência desses testes é o que permitiu os bloqueadores passarem.

**Veredito de maturidade:** código-fonte maduro e limpo (zero TODOs/stubs, contratos completos, lifecycle do SDK correto), mas a **resiliência sob falha** — o que mais importa em mobile — está sub-testada e contém bugs de perda de dados silenciosa. Não está pronto para depender em produção mobile sem corrigir B1 e B2.
