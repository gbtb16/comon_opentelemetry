# Spec — Prontidão do `comon_otel` para adoção no app Flutter mobile

> **Status:** Proposta para revisão
> **Data:** 2026-06-09
> **Autor:** Auditoria multi-agente (time `otel-audit`) + síntese
> **Artefato auditado:** HEAD do fork `serezhia/comon_opentelemetry` (`fbf61da`), adoção planejada via **git dependency no HEAD**
> **Relatórios-fonte (evidência completa `file:line`):** `docs/superpowers/audit/{exporter,propagation,flutter,resilience}-report.md`

---

## 1. Contexto e objetivo

Vamos instrumentar um **app Flutter mobile de produção** com OpenTelemetry usando o fork `comon_otel` (+ `comon_otel_flutter` + `comon_otel_dio`), como alternativa ao package `opentelemetry` do pub.dev, que está estagnado e **não implementa logs**.

Restrições reais do ambiente (fonte: recon de produção da própria empresa):

- **Sinais necessários:** traces **+** metrics **+** logs (os três são cidadãos de primeira classe no pipeline server-side: collector → Tempo / Mimir / Loki).
- **Destino:** OTLP Collector da empresa em `:4318`. O receiver OTLP/HTTP **negocia encoding por `Content-Type`** — aceita `application/json` e `application/x-protobuf` no mesmo endpoint. O cliente React já exporta OTLP/HTTP **JSON** em produção contra esse collector. → **Encoding NÃO é bloqueador.**
- **Endpoint seguro:** o React usa hoje IP público cru (`http://54.172.78.106:4318`), HTTP texto puro, sem auth, CORS `*` — tolerável para browser no domínio, **inaceitável para binário mobile distribuído**. O caminho "certo" para mobile é a rota Traefik `/otel/http` com **TLS + headers de auth**.
- **Backend já instrumentado:** API Java Spring Boot (OTel-Java) e React web já emitem telemetria. O **ganho central do mobile** é costurar o trace `mobile → backend` ponta-a-ponta no Tempo via propagação W3C (algo que o React **não faz hoje** — registra `CompositePropagator` vazio).
- **Contrato de cardinalidade do collector é lei.** O `spanmetrics` connector fixa as dimensões permitidas; atributos com nome fora da lista são dropados, e atributos com nome certo mas **valor de alta cardinalidade** explodem o Mimir. Dimensões permitidas incluem: `http.route`, `http.request.method`, `http.response.status_code`, `token-info.company.name`, `token-info.type`, `db.operation`, `db.system`. Há também `attributes/sanitize` (derruba header `authorization`), `drop_high_cardinality`, `filter/drop_noisy` e `tail_sampling` (8% + erros + lentos).
  - ⚠️ O React emite erroneamente `company.name`/`company.id`, mas a dimensão correta é `token-info.company.name`. **Não repetir esse mismatch no mobile.**

**Objetivo desta spec:** auditoria de prontidão para **adotar com segurança** o fork no app mobile, com plano de correção priorizado (bloqueadores → logo após → roadmap). **Todas as correções dos bloqueadores serão feitas no fork (upstream em `comon_otel`)** e o app dependerá do HEAD corrigido.

---

## 2. Veredito

**O núcleo do fork é genuinamente bom e bem acima do `opentelemetry` estagnado** — não precisa de reescrita:

- 3 sinais completos (traces/metrics/logs);
- exporters OTLP/HTTP **JSON e protobuf** reais e completos (protobuf **não** é stub), além de gRPC;
- configuração OTLP **por sinal** (endpoint/headers/timeout/compressão/retry/backoff/gzip);
- TLS funciona out-of-the-box via `http.Client()` padrão (sem `badCertificateCallback` permissivo);
- propagação W3C correta (traceparent exato, sampling flag real, baggage);
- nomes de atributo HTTP na convenção **estável** (`http.request.method`, `http.response.status_code`, `http.route`, `url.full`) — alinhados ao contrato do collector;
- código limpo (0 TODOs/stubs), contratos de integração implementados, shutdown/forceFlush corretos, span limits spec-compliant.

**Mas NÃO está pronto para mobile sem corrigir 6 bloqueadores**, todos concentrados em **resiliência sob falha** e no **caminho mobile específico** — justamente a camada sub-testada (`comon_otel_flutter` e `comon_otel_dio` têm 1 arquivo de teste cada; os caminhos de resiliência não têm teste). **A maioria dos bloqueadores é correção pequena e cirúrgica.**

---

## 3. O que já está production-ready (não mexer)

Resumo dos pontos fortes confirmados com evidência (detalhe nos relatórios):

| Capacidade | Evidência |
|---|---|
| Exporters OTLP JSON dos 3 sinais | `otlp/json/http_json_{span,metric,log}_exporter.dart`, `Content-Type: application/json`, append `/v1/{traces,metrics,logs}` |
| Protobuf completo (não-stub) | `otlp/protobuf/protobuf_codec.dart` (wire-format manual: spans/events/links/status, métricas sum/gauge/histogram, logs, varint/fixed64) |
| Endpoint HTTPS por sinal + rota custom | `core/otel.dart:84-86,362,527-535` (`appendSignalPath` off quando endpoint por sinal é dado → respeita `/otel/http`) |
| Headers de auth por sinal | `core/otel.dart:98-101,140-158`; `common/exporter_headers.dart:7-24` (não sobrescreve content-type) |
| TLS OK | `common/http_transport.dart:131-132` (`http.Client()` padrão) |
| Retry/backoff/timeout/gzip por sinal | `common/export_retry.dart:6-26`, `common/http_transport.dart:40-48,84-113,150-155` (respeita `Retry-After`) |
| Filas com limite (sem OOM) | `batch_span_processor.dart:42-44` (`maxQueueSize` 2048, drop do mais antigo) |
| Shutdown/forceFlush idempotentes | `batch_span_processor.dart:58-67`, `otel.dart:559-573` |
| traceparent W3C exato + sampling real | `w3c_trace_context_propagator.dart:22-23`, `tracer_provider.dart:98-103` |
| Propagador W3C composto default | `global_propagator.dart:12-14` |
| Nomes HTTP corretos, sem mismatch do React | `semantic_attributes.dart:18,24,33,36` |
| Captura de erro Dart com convenção OTel | `errors/otel_flutter_error_integration.dart:34-49` (`recordException`, `exception.type/message`) |
| Isolate-safe (modelo de memória Dart) | `isolate/otel_isolate.dart` (sem data race; contexto one-way no spawn) |
| **Sampler default = `AlwaysOnSampler`** (compatível com o `tail_sampling` do collector) | `core/otel.dart:260` (`resolvedSampler?.build() ?? const AlwaysOnSampler()`) |
| **Temporality de métrica = cumulative** (Mimir-native) | `metrics/meter.dart:323,398,484` (counters/histograms); codec em `json_codec.dart:359-365` |
| **Correlação log↔trace automática** (logs herdam `trace_id`/`span_id` do contexto ativo) | `logs/log_record.dart:44` (`OtelContext.current.spanContext`), getters `:118,121` |

---

## 4. Fase 1 — BLOQUEADORES (corrigir antes do go-live)

> Todas as correções abaixo são **no fork**. Estimativas de esforço assumem dev familiarizado com Dart; o grosso do custo é **teste**, não código.

### B1 — Envenenamento permanente da cadeia de flush (`_pendingFlush`)

**Severidade: CRÍTICA. Achado independente por 2 auditores.**

`batch_span_processor.dart:69-94` (idêntico em `batch_log_processor.dart:78-103`):

```dart
_pendingFlush = _pendingFlush.then((_) async {   // .then SEM onError
  ...
  await exportFuture.timeout(exportTimeout!);     // lança TimeoutException
  ...
});
```

Em Dart, `Future.then(onValue)` sem `onError` **propaga o erro e pula o `onValue`**. Quando o corpo lança (timeout — caso de rede móvel lenta), `_pendingFlush` vira um Future **permanentemente rejeitado**: toda chamada subsequente faz curto-circuito sobre o erro obsoleto e o callback **nunca mais executa**. O `Timer.periodic` segue disparando contra uma cadeia morta. **Traces + logs param para sempre** até `Otel.init()`/`dispose()`, sem nenhum aviso.

Trigger é padrão em mobile: `exportTimeout` vem de `OTEL_BSP_EXPORT_TIMEOUT`/`OTEL_BLRP_EXPORT_TIMEOUT` (`otel_env_config.dart:139-140,162-163`).

**Correção (fork):** envolver o corpo do callback de `_flushBatch` em `try/catch` para que o Future encadeado **sempre resolva**, sinalizando o erro (ver A-obs) em vez de engolir:

```dart
_pendingFlush = _pendingFlush.then((_) async {
  try {
    // ... corpo atual ...
  } catch (error, stackTrace) {
    _reportError(error, stackTrace);
  }
});
```

Aplicar em `batch_span_processor.dart` **e** `batch_log_processor.dart`.
**Teste obrigatório:** injetar exporter que estoura timeout/lança e verificar que o flush seguinte ainda exporta.
**Esforço:** Baixo.

---

### B2 — Nada sai do device no background/kill + métricas nunca exportadas

**Severidade: CRÍTICA. Achado por 2 auditores (flutter + resilience).**

Dois problemas que se somam:

1. **Sem flush no lifecycle.** `otel_flutter_binding_observer.dart:96-121` (`didChangeAppLifecycleState`) registra durações/breadcrumbs mas **nunca chama `Otel.forceFlush()`** em `paused`/`detached`/`hidden`. Quando o OS suspende/mata o app, a fila em memória (até 2048 itens, `scheduleDelay` default 5s spans / 1s logs) **desaparece — incluindo o crash que acabou de ocorrer**.
2. **Métricas nunca exportadas.** O reader default é `ExportingMetricReader` (`metric_reader.dart:14-48`), que só exporta quando alguém chama `collect()`/`forceFlush()` — **não tem `Timer`**. O `PeriodicMetricReader` só é escolhido via env (`otel.dart:316-326`). Sem isso, **todas** as métricas (`flutter.frame.*`, `flutter.ui.stall.*`, `app.*`) ficam agregadas em memória e morrem com o processo.

**Correção (fork):**
1. No `OtelFlutterBindingObserver`, ao entrar em `paused`/`detached`/`hidden`, disparar `unawaited(Otel.forceFlush())` (guardado por `Otel.isInitialized`). É o único ponto confiável antes do OS matar o processo.
2. Garantir `PeriodicMetricReader` em mobile por default (intervalo 30-60s) — ou via parâmetro de `Otel.init`/`ComonOtelFlutter.install` (ver B3, mesma raiz: config inalcançável).

**Teste obrigatório:** simular transição para `paused` e verificar `forceFlush` chamado; verificar que métricas são exportadas periodicamente.
**Esforço:** Baixo-médio.

---

### B3 — Batching/metric-reader inalcançáveis pela API pública no mobile

**Severidade: ALTA.**

`Otel.init` (`otel.dart:80-116`) **não expõe** `useBatchSpanProcessor`/`maxQueueSize`/`scheduleDelay`/`usePeriodicMetricReader`. A única forma de ligar é via env (`otel.dart:207,212`; `otel_env_config.dart:151`), e no Flutter mobile `Platform.environment` é vazio (`--dart-define` **não** popula esse mapa). Resultado: default cai em `SimpleSpanProcessor` = **1 POST HTTP por span** (`simple_span_processor.dart:18-31`), `SimpleLogProcessor` por log, `ExportingMetricReader` (ver B2). Em rede móvel = bateria/latência/perda em massa.

**Correção (fork):** expor na API de `Otel.init` (e propagar para `OtelConfig`) os controles de processor/reader:
- `bool useBatchSpanProcessor`, `bool useBatchLogProcessor`, `bool usePeriodicMetricReader`
- `Duration scheduleDelay`, `int maxQueueSize`, `int maxExportBatchSize`, `Duration metricExportInterval`

**Escape hatch que já existe hoje** (documentar como workaround imediato enquanto a API não é expandida): pré-construir `BatchSpanProcessor`/`BatchLogProcessor` e passar via `spanProcessors:`/`logProcessors:` — quando a lista é não-vazia ela tem prioridade (`otel.dart:288-289,329-330`).
**Esforço:** Baixo.

---

### B4 — Spans de rota não parenteiam → árvore de trace quebrada

**Severidade: ALTA (quebra o objetivo central de correlação).**

`otel_navigator_observer.dart:100` cria o span de rota com `startSpan` direto, guarda em `_activeSpans`, mas **nunca o ativa no contexto** (`OtelContext.withSpan`). Como o parent default é `OtelContext.currentSpan` (`tracer_provider.dart:70`) — um valor de Zone só populado dentro de `withSpan` — o span de rota nunca vira `current`. Consequência: cada interação/HTTP captura `currentSpan == null` e vira **trace-raiz solto**, não filho da tela. Agravante (B3 do relatório Flutter): o span de rota dura toda a permanência na tela (minutos/horas → anti-padrão "span guarda-chuva") e embute o nome da rota, com risco de cardinalidade se a rota tiver ID dinâmico.

#### Trade-off de modelo (decisão a tomar nesta spec)

**Opção A — Span curto de transição + correlação por atributo (RECOMENDADA):**
A navegação vira um span **curto** (`screen_load`, do push até o primeiro frame "ready", ~centenas de ms, com nome de rota **sanitizado** tipo `/order/:id`). As interações e chamadas HTTP continuam como seus próprios traces, e a correlação com a tela é feita por **atributo** (`screen.name`/`flutter.route.name`) presente nos spans — consultável no Tempo/Grafana.

- ✅ Sem spans guarda-chuva de horas; sem risco de cardinalidade no nome do span; alinhado a como SDKs mobile maduros (Datadog RUM, Sentry) modelam "views" vs "actions".
- ✅ O elo `mobile → backend` (o ganho principal) continua intacto via propagação W3C.
- ⚠️ Não produz literalmente uma única árvore `route → interaction → http` no waterfall; a correlação é por atributo/consulta, não por parentesco.

**Opção B — Span de tela vivo e ativado como parent:**
Manter o span de rota durante a presença na tela **e** ativá-lo no contexto (propagando-o como `parent:` explícito nas interações via `OtelFlutterRouteContext`, que hoje só carrega o nome — faltaria carregar o `Span`/`SpanContext`).

- ✅ Produz a árvore visual `tela → interação → HTTP → backend` que foi o pedido literal.
- ❌ Spans de duração de minutos/horas são anti-padrão de tracing (inflam duração, viram "guarda-chuva" sem semântica de operação); maior risco de cardinalidade; exige carregar `Span` no route context e disciplina de parent em todas as interações.

**Recomendação:** **Opção A.** Entrega o valor real (correlação tela↔interação↔backend) sem os anti-padrões da B; o waterfall literal sob um span de tela de horas custa caro em armazenamento e cardinalidade e não agrega diagnóstico proporcional. A decisão final fica registrada aqui para o plano de implementação.

**Esforço:** Médio (decisão de modelo + sanitização de nome de rota + atributo de correlação).

---

### B5 — Interceptor Dio sem try/catch → instrumentação derruba a request real

**Severidade: ALTA (segurança de produção).**

`otel_dio_interceptor.dart:78-142` (`onRequest`, idem `onResponse`/`onError`): não há `try/catch` em torno de `startSpan`/`inject`/captura de headers. Se qualquer chamada lançar (sampler custom com bug, carrier malformado), `handler.next(options)` (linha 141) **nunca é chamado** e a request real do usuário trava/falha. Telemetria opcional vira ponto único de falha do app.

**Correção (fork):** envolver toda a lógica de telemetria em `try/catch` que **sempre** chama `handler.next(...)`:

```dart
void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
  try {
    // ... toda a lógica de span/inject ...
  } catch (_) {
    // swallow — instrumentação nunca quebra a request
  }
  handler.next(options);
}
```

Equivalente garantindo `handler.next` em `onResponse`/`onError`.
**Esforço:** Baixo.

---

### B6 — `http.route` com path cru → explosão de cardinalidade no Mimir

**Severidade: ALTA (dano à infra compartilhada). Correção trivial.**

`otel_dio_interceptor.dart:92`:

```dart
SemanticAttributes.httpRoute: uri.path.isEmpty ? '/' : uri.path,
```

`SemanticAttributes.httpRoute == 'http.route'` (`semantic_attributes.dart:33`) — dimensão **permitida** do spanmetrics. O valor é o path concreto com IDs (`/users/12345`). Como o **nome** está correto, o filtro `drop_high_cardinality`/sanitize **não** o derruba → cada ID vira uma série métrica nova no spanmetrics → polui o Mimir de toda a empresa. Agravante semântico: `http.route` é atributo de **server**; num span `SpanKind.client` o Dio não conhece o template de rota do backend.

**Correção (fork):** **não emitir `http.route` no client** (remover a linha 92). O backend Java já emite o `http.route` correto (template). Se quiser uma dimensão estável de baixa cardinalidade no client, derivar um template via `spanNameBuilder`/filtro — **nunca** o path cru.
**Esforço:** Trivial.

---

## 5. Fase 2 — LOGO APÓS (alto valor, não bloqueia o go-live)

Todas no fork, salvo onde indicado.

### F2.1 — Resource incompleto para mobile + `host.name` vaza PII
`core/resource.dart:43-46` + `platform_runtime_io.dart:13-30` só produzem `process.*`, `os.type`, `os.description`, `host.name`. **Ausentes:** `telemetry.sdk.{name,language,version}` (grep = zero — a spec OTel os marca obrigatórios), `device.model.identifier`/`device.manufacturer`, `os.name`/`os.version` separados, `service.version` (sem param em `init` — só via `resourceAttributes` manual). **PII:** `host.name = Platform.localHostname` em iOS/Android costuma ser "iPhone de João".
**Correção:** adicionar detector mobile (`device_info_plus`/`package_info_plus`) populando `device.*`, `os.name/version`, `service.version`, `telemetry.sdk.*`; adicionar `serviceVersion` a `Otel.init`; remover/anonimizar `host.name` em mobile.

### F2.2 — Falhas de export 100% silenciosas (sem observabilidade do SDK)
`ExportResult.failure` descartado pelo batch (`batch_span_processor.dart:82-89`); overflow dropa sem contador (`:42-44`); `.catchError((_){})` nos Simple processors (`simple_span_processor.dart:27`, `simple_log_processor.dart:23`). O operador não tem como saber que telemetria está caindo.
**Correção:** hook global de erro do SDK (estilo `OpenTelemetry.errorHandler`) + contador de `droppedCount`/exports falhos emitido como métrica/log interno.

### F2.3 — Zero scrubbing de PII em valores de atributo
Única redação existente é **header-only no Dio** (`otel_dio_interceptor.dart:24,64,266`). Não há redação de **valores** de atributo de span/log; `span.dart` só limita contagem/cardinalidade, não conteúdo.
**Correção:** `SpanProcessor`/`LogProcessor` de redação configurável (allow/deny-list de chaves + função de transformação) executado antes do export.

### F2.4 — `url.full` com query string completa → PII/bloat no Tempo
`otel_dio_interceptor.dart:91` (`uri.toString()` inclui `?token=...&cpf=...`). Não explode cardinalidade métrica (`url.full` não está na allowlist), mas vaza PII no trace storage.
**Correção:** redigir query string ou setar só `url.path`/`url.scheme`/`server.address`.

### F2.5 — UI stall: falso positivo no resume + overhead permanente
`otel_flutter_ui_stall_observer.dart:82-85` usa `Timer.periodic(50ms)` permanente sem gating de lifecycle → "stall" gigante espúrio no resume + 20 wakeups/s contínuos (bateria).
**Correção:** pausar o timer em `paused`/`hidden`, resetar `_lastTickAt` no `resumed`; considerar intervalo maior/desligado por default.

### F2.6 — Handlers de erro Flutter sem try/catch
`errors/otel_flutter_error_integration.dart` substitui `FlutterError.onError`/`PlatformDispatcher.onError`; se a gravação OTel lançar, quebra o handler de erro do app — pior justo no caminho de captura de crash.
**Correção:** `try/catch` nas gravações, sempre delegando ao `fallback`/`presentError`.

### F2.7 — JSON de métricas usa número para int64 (interop)
`json_codec.dart:340,350,354` emite `asInt`/`count`/`bucketCounts` como número JSON; a spec OTLP/JSON pede int64 como **string** (precisão > 2^53). Traces/logs corretos. Collector geralmente tolera, mas é não-conforme.
**Correção:** serializar esses campos como string.

---

## 6. Fase 3 — ROADMAP / DEPOIS (diferenciais de maturidade)

### F3.1 — Persistência offline em disco
Filas são 100% em memória (`batch_span_processor.dart:27`, `batch_log_processor.dart:36`); grep por persistência = zero. Mesmo com o `forceFlush` da B2, dados em rede caída se perdem.
**Proposta:** buffer offline append-only (`path_provider`) drenado no próximo cold start — o que Sentry/Datadog RUM fazem. Maior item de engenharia do roadmap.

### F3.2 — Captura de crash nativo
Hoje só mundo Dart (`FlutterError.onError` + `PlatformDispatcher.onError`). **Não** captura SIGSEGV/ANR, exceções em plugins nativos, isolates secundários sem zone. (Limite honesto.)
**Proposta:** integração com Crashlytics/Sentry-native ou signal handler nativo; ou documentar o limite e cobrir com solução nativa complementar.

### F3.3 — Cobertura de testes da camada mobile/resiliência
Core tem ~4.700 linhas de teste; `comon_otel_flutter` e `comon_otel_dio` têm **1 arquivo cada**. B1/B2 não tinham teste — foi o que deixou os bugs passarem.
**Proposta:** suíte de resiliência (chain poisoning, perda no lifecycle, drop em failure/overflow) + testes de lifecycle observer, error hooks, frame timing, navigation, e do interceptor Dio.

### F3.4 — Startup real (cold start)
`otel_flutter_startup_tracker.dart:45-64` mede "init → primeiro frame", não cold start real (perde engine boot). `appStartupStartTime` é null por default.
**Proposta:** capturar timestamp de plataforma no `main` antes de qualquer await e passar via `appStartupStartTime`; distinguir cold vs warm.

---

## 7. Plano de verificação

A correção não é "feita" até ser verificada empiricamente — não só por leitura/teste unitário.

1. **Stack demo end-to-end (já existe no repo):** `demo/otel_end_to_end/docker-compose.yml` (collector + Jaeger + backend Dart instrumentado). Subir e validar o caminho de export + propagação W3C com o exemplo Flutter apontando para o collector local, confirmando que o trace costura mobile → backend.
2. **Testes de resiliência (TDD):** para B1, B2, F2.2 — escrever o teste que falha **antes** da correção (ex.: exporter que estoura timeout → verificar que o próximo flush ainda exporta).
3. **Validação contra o collector real da empresa (staging):** confirmar (a) OTLP/HTTP JSON aceito na rota `/otel/http` com TLS + headers de auth; (b) atributos chegam com os nomes do contrato de cardinalidade; (c) nenhum atributo de alta cardinalidade (pós-B6) chega ao spanmetrics.
4. **Alinhamento de atributos com o contrato do collector:** garantir que os spans/métricas do mobile usem `http.request.method`, `http.response.status_code`, `http.route` (template, não path cru), e `token-info.company.name` (não `company.name`) onde aplicável.

### Corretude dos 3 sinais no SEU backend (verificado — manter como checks de regressão)

Estes três pontos decidem se metrics/logs (não só traces) chegam **corretos** ao Mimir/Loki — foram verificados no HEAD e **passam**; manter como checks explícitos:

5. **Sampler não pode dropar no cliente o que o collector tail-sampleia.** O collector retém erros + traces lentos via `tail_sampling`, o que **só funciona se o cliente exportar esses traces**. O default do fork é `AlwaysOnSampler` (`core/otel.dart:260`) → ✅ correto. **Guidance de configuração (importante):** **não** definir um `TraceIdRatioSampler`/head sampler no cliente para "economizar banda" — isso dropa erros no device antes do tail-sampling e anula a política do collector. Deixar o sampling a cargo do collector.
6. **Temporality de métrica = cumulative** (`metrics/meter.dart:323,398,484`) → ✅ compatível com Prometheus/Mimir (cumulative-native). Se algum dia for trocado para `delta`, o collector precisaria de um `delta-to-cumulative` processor. Validar no staging que `flutter.frame.*`/`app.*` aparecem corretos no Mimir.
7. **Correlação log↔trace** — `LogRecord` captura `OtelContext.current.spanContext` no momento da emissão (`logs/log_record.dart:44`) → ✅ logs carregam `trace_id`/`span_id` do trace ativo. Validar no Loki/Grafana que o "trace to logs" funciona (logs emitidos dentro de um span aparecem correlacionados).

---

## 8. Resumo de priorização

| Fase | Itens | Bloqueia go-live? | Esforço agregado |
|---|---|---|---|
| **1 — Bloqueadores** | B1, B2, B3, B4, B5, B6 | **Sim** | Baixo-médio (grosso é teste; B4 é a maior decisão de design) |
| **2 — Logo após** | F2.1–F2.7 | Não | Médio |
| **3 — Roadmap** | F3.1–F3.4 | Não | Alto (F3.1 e F3.3 são os maiores) |

**Caminho crítico mínimo para produção:** B1 + B2 + B3 + B5 + B6 (todos baixo/trivial) tornam o pipeline **confiável e seguro**; B4 entrega a **correlação de tela** (decisão: Opção A). F2.1 (PII em `host.name` + resource) é fortemente recomendado entrar junto por ser dado sensível de usuário.

---

## 9. Decisões registradas

- **Onde corrigir:** todas as correções de bloqueadores **no fork** (`comon_otel`), app depende do HEAD corrigido.
- **B4:** **Opção A** (span curto de transição + correlação por atributo).
- **Escopo da spec:** completa (bloqueadores + logo após + roadmap).
- **Encoding OTLP:** JSON é suficiente (collector negocia por Content-Type; React já usa JSON em prod). Não é bloqueador.
