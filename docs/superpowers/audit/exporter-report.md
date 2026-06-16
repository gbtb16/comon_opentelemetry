# Auditoria — Caminho de Export OTLP (`comon_otel`)

Escopo: caminho de export OTLP/HTTP (JSON e protobuf) do package `comon_otel`, julgado para o cenário de produção mobile (Flutter → OTLP Collector `:4318`, rota Traefik `/otel/http` com TLS + headers de auth). Toda evidência cita `arquivo.dart:linha`.

## Resumo

O caminho OTLP/HTTP está, no núcleo, **bem implementado e production-ready** para o cenário mobile: os 3 sinais (traces, metrics, logs) têm exporter JSON **e** protobuf funcionais e completos (protobuf NÃO é stub); endpoint, headers de auth, timeout, compressão e retry/backoff são todos configuráveis **por sinal**; TLS funciona via `http.Client()` padrão sem nada que impeça HTTPS; e a falha de export é engolida sem derrubar o app. Há, porém, **dois bloqueadores reais para mobile**: (1) o batching só liga via variáveis de ambiente `OTEL_BSP_*` que no Flutter mobile ficam vazias, então o default vira **uma requisição HTTP por span** (`SimpleSpanProcessor`); (2) quando um `exportTimeout` está configurado e estoura, a cadeia de flush do batch processor é **permanentemente envenenada** (exports param para sempre + erro assíncrono não observado a cada tick). Além disso, `telemetry.sdk.*` não é setado em lugar nenhum e `service.version` não tem parâmetro dedicado em `Otel.init`.

---

## BLOQUEADORES (impedem adoção segura agora)

### B1 — Batching não é ativável no mobile pela API pública; default é 1 POST por span

**Evidência:**
- `Otel.init` (`core/otel.dart:80-116`) **não expõe** nenhum parâmetro `useBatchSpanProcessor`, `maxQueueSize`, `scheduleDelay` etc.
- A única forma de ligar o batch processor automático é via env: `useBatchSpanProcessor: OtelEnvConfig.hasBspConfig` (`core/otel.dart:207`), e `hasBspConfig` depende de `OTEL_BSP_*` (`core/otel_env_config.dart:151-155`). Mesmo para logs: `useBatchLogProcessor: OtelEnvConfig.hasBlrpConfig` (`core/otel.dart:212`).
- No Flutter mobile `Platform.environment` (`core/platform_runtime_io.dart:3`) é efetivamente vazio e `--dart-define` não popula esse mapa. Logo `hasBspConfig == false` → `_buildSpanProcessors` cai no fallback `SimpleSpanProcessor` (`core/otel.dart:307`), que exporta **cada span individualmente** num POST próprio (`trace/simple_span_processor.dart:18-31`). Idem logs → `SimpleLogProcessor` (`core/otel.dart:349`); métricas → `ExportingMetricReader` (`core/otel.dart:326`).

**Por que bloqueia mobile:** rede móvel instável + 1 conexão HTTP TLS por span = bateria, latência e perda massiva sob rede ruim. Contradiz diretamente o requisito de produção "batching/retry robustos p/ rede móvel".

**Correção concreta:** expor batching na API `Otel.init` (ex.: `bool useBatchSpanProcessor`, `Duration scheduleDelay`, `int maxQueueSize`, `int maxExportBatchSize`) repassando para a `OtelConfig`. **Escape hatch existente hoje:** o app pode pré-construir `BatchSpanProcessor`/`BatchLogProcessor` e passar via `spanProcessors:`/`logProcessors:` — quando essa lista é não-vazia ela tem prioridade (`core/otel.dart:288-289`, `329-330`). É o **único** caminho atual para batching no mobile e deve ser documentado.

### B2 — `exportTimeout` no batch processor envenena permanentemente a fila de export

**Evidência:**
- `BatchSpanProcessor._flushBatch` encadeia `_pendingFlush = _pendingFlush.then((_) async {...})` **sem handler de erro** (`trace/batch_span_processor.dart:70`). Dentro do callback, quando há timeout: `await exportFuture.timeout(exportTimeout!)` (`trace/batch_span_processor.dart:87`) lança `TimeoutException`.
- Como o `.then` não tem segundo argumento (`onError`), o `_pendingFlush` vira um future rejeitado. Toda chamada subsequente de `_flushBatch` faz `_pendingFlush.then(...)` que **só propaga o erro e nunca executa o callback** → exports param para sempre. Mesma estrutura no log processor: `logs/batch_log_processor.dart:79` + `:96`.
- Cada disparo é `unawaited(_flushBatch())` no `Timer.periodic` (`trace/batch_span_processor.dart:17-19`) e no `onEnd` (`:49`) → erro assíncrono não observado a cada tick.

**Por que bloqueia mobile:** interação tóxica com B1 — a env var que liga o batch processor (`OTEL_BSP_EXPORT_TIMEOUT`) é a mesma que arma esse bug. Em rede móvel lenta, um único timeout mata o pipeline de telemetria silenciosamente pelo resto da sessão e gera erros assíncronos não observados.

**Correção concreta:** envolver o corpo do callback de `_flushBatch` em `try/catch` (engolir/logar a falha por batch, sem rejeitar `_pendingFlush`), ou anexar `.catchError(...)` à cadeia para que o próximo flush não herde o estado rejeitado. Aplicar em `batch_span_processor.dart` e `batch_log_processor.dart`.

---

## ATENÇÃO (corrigir cedo, não bloqueia)

### A1 — `telemetry.sdk.*` ausente

Grep em todo `lib/` retorna zero ocorrências de `telemetry.sdk`. O detector de recurso (`core/platform_runtime_io.dart:13-22`) seta `process.*`, `os.*`, `host.name`, mas **não** `telemetry.sdk.name/language/version`. A spec OTel marca esses como obrigatórios no resource; sua ausência pode confundir dashboards/processadores no Collector. Correção: adicionar `telemetry.sdk.name=opentelemetry`, `telemetry.sdk.language=dart`, `telemetry.sdk.version=<versão do package>` no `Resource.autoDetect` ou nos detectores default (`core/resource.dart:81-103`).

### A2 — `service.version` e `deployment.environment` sem ergonomia de primeira classe

`Otel.init` aceita `environment` (`core/otel.dart:87`) → mapeado para `deployment.environment` em `Resource` (`core/resource.dart:73-75`). Mas **não há parâmetro `serviceVersion`** em `init`; só dá para setar via `resourceAttributes: {'service.version': ...}` (manual). O construtor `Resource` até suporta `serviceVersion` (`core/resource.dart:59`,`67-69`), mas `init` nunca o usa. Correção: adicionar `serviceVersion` a `Otel.init` e repassar.

### A3 — Falha de export é 100% silenciosa (sem observabilidade)

`executeOtlpExportWithRetry` tem `catch (_)` que engole qualquer exceção de rede (`exporters/otlp/common/export_retry.dart:55-59`) e retorna `ExportResult.failure`. Os processors **descartam** o `ExportResult` sem inspecioná-lo (`trace/batch_span_processor.dart:83`, `simple_span_processor.dart:27` faz `.catchError((_) {})`). O único `print` existente é em **partial success** (`exporters/otlp/common/export_response.dart:25`), não em falha total. Bom para "não derrubar o app", ruim para diagnosticar telemetria que some. Correção: hook/callback opcional de erro ou log diagnóstico em falha de export.

### A4 — JSON de métricas usa números para campos int64 (interop)

No JSON codec, `asInt` em number data points emite o int como **número JSON** (`exporters/otlp/json/json_codec.dart:340`), e `count`/`bucketCounts` do histograma idem (`:350`,`:354`). A spec OTLP/JSON pede int64 como **string** (precisão acima de 2^53). Traces e logs estão corretos (timestamps `unixNano` como string em `:301-304`, `intValue` de atributos como string em `:284`, IDs como hex em `:135`,`:167`), então o risco fica restrito a métricas com contadores grandes; jsonpb leniente do Collector geralmente aceita, mas é não-conforme. Correção: serializar `asInt`/`count`/`bucketCounts` como string.

### A5 — Transport HTTP é único e compartilhado entre os 3 sinais

`config.otlpTransport` é passado igual para traces/metrics/logs (`core/otel.dart:365`,`411`,`457`). Headers/endpoint/timeout/compressão/retry são por sinal, mas o `OtlpHttpTransport` (e portanto o pool de conexões / config de TLS customizada) não. Para `:4318` único é irrelevante; só limita cenários de cliente HTTP distinto por sinal.

### A6 — `IoOtlpHttpTransport` deprecado e `_requireEndpoint` para gRPC

`IoOtlpHttpTransport` está `@Deprecated` (`exporters/otlp/common/http_transport.dart:171-174`) — limpar referências em apps. Menor.

---

## OK / PONTOS FORTES (com evidência)

1. **Os 3 sinais têm exporter OTLP/HTTP JSON funcional.** `OtlpHttpJsonSpanExporter` / `OtlpHttpJsonMetricExporter` / `OtlpHttpJsonLogExporter` (`json/http_json_span_exporter.dart`, `..._metric...`, `..._log...`), todos com `content-type: application/json` (`:65`), append automático de `/v1/traces|metrics|logs` (`json/http_json_span_exporter.dart:50`). Codec JSON correto para o caminho mobile crítico: IDs hex (`json_codec.dart:135`), timestamps `unixNano` como string (`:301-304`), `intValue` de atributos como string (`:284`).

2. **Protobuf está COMPLETO, não é stub.** `OtlpProtobufCodec` (`protobuf/protobuf_codec.dart`) implementa encoding manual de wire-format: spans com events/links/status (`:118-173`), métricas sum/gauge/histogram com temporality e packed fields (`:204-285`), logs com severity/trace context (`:313-328`), varint/fixed64/double/signed-varint (`:436-530`). `OtelExporter.otlpHttp` mapeia para o exporter **protobuf** (`core/otel.dart:357`); `otlpHttpJson` é separado (`:369`). `content-type: application/x-protobuf` (`protobuf/http_protobuf_span_exporter.dart:64`).

3. **Endpoint HTTPS customizável por sinal.** `tracesEndpoint`/`metricsEndpoint`/`logsEndpoint` em `init` (`core/otel.dart:84-86`) com fallback para `endpoint` compartilhado (`core/otel.dart:527-535`). Quando o endpoint por sinal é dado, `appendSignalPath` é desligado (`core/otel.dart:362`) → respeita rota custom como `/otel/http`. `resolveOtlpSignalUri` normaliza paths corretamente (`common/http_transport.dart:177-191`). Também via env `OTEL_EXPORTER_OTLP_*_ENDPOINT` (`otel_env_config.dart:34-45`).

4. **Headers de auth customizáveis por sinal.** `otlpHeaders` (global) + `otlpTracesHeaders`/`otlpMetricsHeaders`/`otlpLogsHeaders` em `init` (`core/otel.dart:98-101`), merge com precedência por sinal (`core/otel.dart:140-158`). Também via env `OTEL_EXPORTER_OTLP_[TRACES|METRICS|LOGS]_HEADERS` (`otel_env_config.dart:62-75`). Os headers chegam ao request sem sobrescrever `content-type`/`content-encoding` (`common/exporter_headers.dart:7-24`).

5. **TLS OK — nada impede HTTPS no mobile.** `DefaultOtlpHttpTransport` usa `http.Client()` padrão (`common/http_transport.dart:131-132`) com validação de certificado normal do `package:http`. Sem `badCertificateCallback` permissivo, sem desabilitar TLS. HTTPS para `:4318`/Traefik funciona out-of-the-box.

6. **Retry/backoff/timeout/gzip robustos.** Retry exponencial com `maxAttempts`, `initialDelay`, `backoffMultiplier`, `maxDelay` (`common/export_retry.dart:6-26`), respeitando `Retry-After` em 429/503 (`common/http_transport.dart:84-113`, `export_retry.dart:51-54`) e só re-tentando status retryable 429/502/503/504 (`http_transport.dart:77-81`). Timeout por request aplicado em send **e** leitura do body (`http_transport.dart:150-155`). gzip suportado por sinal (`common/http_transport.dart:40-48`, header em `exporter_headers.dart:22`). Tudo configurável por sinal (`core/otel.dart:367`,`379` etc.).

7. **Falha de export NÃO derruba o app.** O exporter OTLP nunca lança: o retry engole tudo (`export_retry.dart:55`) e retorna `ExportResult.failure`. `SimpleSpanProcessor` ainda blinda com `.catchError((_) {})` (`simple_span_processor.dart:27`). Única ressalva é o caminho de timeout do batch processor (ver B2). Fora isso, falha de rede = telemetria perdida silenciosamente, app intacto.

8. **Filas com limite e drop do mais antigo.** `BatchSpanProcessor`/`BatchLogProcessor` têm `maxQueueSize` (default 2048) e descartam o item mais antigo quando enchem (`batch_span_processor.dart:42-44`, `batch_log_processor.dart:49-51`) — backpressure correto, sem crescimento ilimitado de memória. `maxBatchSize` default 512, flush por tamanho ou por timer.

---

## Veredito para mobile

Núcleo OTLP/HTTP sólido e production-ready (endpoint/headers/TLS/retry/gzip por sinal, JSON+protobuf completos, falha não derruba app). **Não adote como está sem antes:** (B1) garantir batching no mobile — hoje só via `spanProcessors:`/`logProcessors:` pré-construídos, idealmente expor na `init`; e (B2) corrigir o envenenamento da fila de flush sob `exportTimeout`. A1/A2 (telemetry.sdk + service.version) devem entrar cedo para qualidade de resource no Collector.
