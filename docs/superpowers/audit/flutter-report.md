# Auditoria de Instrumentação Flutter — `comon_otel_flutter`

Escopo: `packages/comon_otel_flutter` + dependências relevantes em `packages/comon_otel`.
Destino de produção: app mobile real → OTLP Collector → Tempo/Mimir/Loki.

## Resumo (3-5 linhas)

A instrumentação cobre uma superfície ampla e correta de sinais (lifecycle, navegação, startup, frames, UI stall, erros, interações, breadcrumbs) com bom isolamento por `Otel.isInitialized`. Porém há **dois bloqueadores de telemetria**: (1) **métricas essencialmente nunca são exportadas** — o reader default é sob demanda e nada no app chama `forceFlush`, então frame/jank/stall/lifecycle/memory-pressure ficam agregadas em memória e morrem com o processo; (2) **não há flush algum quando o app vai a `paused`/`detached`**, agravando a perda. Além disso, **spans de rota não parenteiam nada** (não são ativados no contexto), o que quebra a correlação tela→interação→HTTP→backend que é o objetivo central. Resource attributes mobile (`device.*`, `service.version`, `telemetry.sdk.*`) estão **ausentes** e `host.name` vaza PII. Observers **não têm try/catch** — um erro de instrumentação pode propagar.

---

## BLOQUEADORES

### B1 — Métricas nunca são exportadas em operação normal + nenhum flush no lifecycle

**Evidência (reader default é sob demanda):**
`comon_otel/lib/src/metrics/metric_reader.dart:14-48` — `ExportingMetricReader.collect()` só exporta quando alguém chama `collect()`/`forceFlush()`. **Não há `Timer` nem periodicidade interna.**

```dart
final class ExportingMetricReader implements MetricReader {
  @override
  Future<void> collect() async { ... await exporter.export(metrics); }
  @override
  Future<void> forceFlush() async { await collect(); await exporter.forceFlush(); }
}
```

`comon_otel/lib/src/core/otel.dart:316-326` — o reader periódico só é escolhido se `usePeriodicMetricReader` (que vem de `OtelEnvConfig.hasMetricReaderConfig`); sem env config, cai em `ExportingMetricReader`:
```dart
if (config.usePeriodicMetricReader) { return <MetricReader>[PeriodicMetricReader(...)]; }
return <MetricReader>[ExportingMetricReader(exporter: exporter)];
```

**Evidência (nada chama flush):** `forceFlush` só aparece nos testes (`test/comon_otel_flutter_test.dart`, ~20 chamadas), nunca no código de produção do pacote. O lifecycle observer `didChangeAppLifecycleState` (`lifecycle/otel_flutter_binding_observer.dart:96-121`) registra log/breadcrumb/durations mas **não chama `Otel.forceFlush()`** em nenhum estado:
```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  OtelFlutterBreadcrumbs.add(...);
  if (Otel.isInitialized) { _recordLifecycleDurations(state); if (logLifecycleTransitions) {...log...} }
  _lastLifecycleState = state;          // <- sem forceFlush em paused/detached
}
```

**Impacto:**
- **Todas as métricas** definidas pelo pacote (`flutter.frame.duration`, `flutter.frame.slow.count`, `flutter.frame.jank.count`, `flutter.ui.stall.*`, `app.foreground/background.duration`, `app.memory_pressure.count`) são agregadas em memória e **nunca saem do device** com a config default — performance de frames/UI fica invisível no Mimir.
- Spans/logs usam `SimpleSpanProcessor`/`SimpleLogProcessor` por default (`otel.dart:307,349`), que exportam por span/log finalizado — portanto traces/logs *não* dependem de flush, mas qualquer span ainda aberto (ver B2/B3) ou item em retry pendente ao matar o app se perde, e sem flush em `detached` não há janela para drenar.

**Correção concreta:**
1. No `OtelFlutterBindingObserver.didChangeAppLifecycleState`, ao entrar em `AppLifecycleState.paused`/`detached`/`hidden`, disparar `unawaited(Otel.forceFlush())` (guardado por `Otel.isInitialized`). É o único ponto confiável antes do SO matar o processo mobile.
2. Para métricas, garantir um `PeriodicMetricReader` em mobile (ex.: intervalo de 30-60s) ou documentar que `ComonOtelFlutter.install` exige config de metric reader; caso contrário a telemetria de performance é puramente decorativa.

---

### B2 — Spans de rota não são parenteados (quebram correlação tela → interação → HTTP)

**Evidência:** O navigator observer cria o span de rota com `startSpan` direto, guarda em `_activeSpans` e **nunca o ativa no contexto** (`navigation/otel_navigator_observer.dart:100-117`):
```dart
final span = Otel.instance.tracer.startSpan('$spanNamePrefix $routeName', ...);
_activeSpans[route] = span;   // nunca vira OtelContext.currentSpan
```
O parent default é resolvido por `tracer_provider.dart:70`: `final currentParent = parent ?? OtelContext.currentSpan;`. E `currentSpan` é um valor de Zone (`context/otel_context.dart:101`), só populado dentro de `OtelContext.withSpan` (`trace/tracer_extensions.dart:26,56`).

Como o span de rota é criado **fora** de qualquer `withSpan`/Zone e nunca passa `parent:`, ele não se torna current. Consequências verificáveis no código:
- O `screen_ready` span (`otel_navigator_observer.dart:191`) é criado igual — é **irmão**, não filho do span de rota.
- As interações (`interactions/otel_flutter_interactions.dart:82-88,115-122`) usam `tracer.trace`/`traceAsync`, que ativam o span via `withSpan` corretamente para seus sub-spans (ex.: o `frontend.submit_order_request` do exemplo fica filho do span de interação). **Porém** a interação em si captura `OtelContext.currentSpan` no momento do tap = `null` (a rota não está ativa) → o span de interação é **root solto**, não filho da tela.

**Impacto:** No Tempo, cada tela vira um trace isolado de longuíssima duração (ver B3) e cada tap/HTTP vira outro trace raiz. Não há a árvore `route → interaction → http.client → backend` que o objetivo da auditoria pede. A correlação com o backend continua funcionando (o `propagator.inject` no exemplo propaga o trace da interação), mas o elo com a tela é perdido.

**Correção concreta:** Decidir o modelo: ou (a) o span de rota é curto (abre/fecha na transição — ver B3) e serve só como marco, deixando interações como traces próprios; ou (b) manter o span de rota vivo e ativá-lo no contexto. Para (b), o `startSpan` direto não basta — seria preciso propagar o span de rota como parent explícito nas interações (`OtelFlutterRouteContext` já carrega o nome; faltaria carregar o `Span`/`SpanContext` e passar via `parent:`/`parentContext:` em `traceAction`/`traceAsyncAction`).

---

### B3 — Span de rota dura toda a permanência na tela (spans de horas; alto risco de cardinalidade de nome)

**Evidência:** `didPush` abre o span (`otel_navigator_observer.dart:35-37` → `_startRouteSpan`) e ele só termina em `didPop`/`didRemove`/`didReplace` (`:40-57`, `_endRouteSpan` em `:150-164`). O nome do span embute o nome da rota: `'$spanNamePrefix $routeName'` (`:101`), e `_routeName` cai no `route.settings.name` (`:228-234`).

**Impacto:**
- Um span que cobre todo o tempo que a tela fica empilhada (pode ser minutos/horas) é um anti-padrão para tracing — vira um "span guarda-chuva" sem semântica de operação, infla a duração e (combinado com B2) não tem filhos.
- **Cardinalidade alta no nome do span**: se rotas usarem nomes dinâmicos com ID (`/order/123`, `/user/abc`), o nome do span explode. O contrato do Collector lista as dimensões permitidas de spanmetrics; `flutter.route` / nome de span não está entre elas, então spans de rota com ID dinâmico viram ruído/risco no spanmetrics. O `screen.name`/`flutter.route.name` (`:106-108`) replicam esse valor não-normalizado.

**Correção concreta:** Transformar a navegação em **span curto de transição** (push/pop como evento ou span de poucos ms) em vez de span de presença; e/ou exigir nomes de rota estáveis e oferecer um sanitizador (ex.: `/order/:id`) antes de usar como nome de span/atributo, espelhando a convenção `http.route` que o Collector aceita.

---

## ATENÇÃO

### A1 — Startup não mede cold start real e não distingue cold/warm
`startup/otel_flutter_startup_tracker.dart:45-50` abre o span `app.startup` no momento de `install()`, com `startTime` = `config.appStartupStartTime` que é **null por default** (`comon_otel_flutter_config.dart:50`). Como `install()` roda **depois** de `Otel.init()` no `main` (ver `example/lib/main.dart:9-19`), o span começa já tardiamente e **perde toda a fase pré-init** (engine boot, `runApp` anterior). Ele apenas mede `install → primeiro post-frame callback` (`startup_tracker.dart:60-64`). Não há nenhuma distinção cold vs warm start. Para cold start real seria preciso capturar um timestamp de plataforma (engine/`DateTime` no `main` antes de qualquer await) e passá-lo via `appStartupStartTime`. Correto reportar como "tempo até primeiro frame após init", não como cold start.

### A2 — UI stall: falso positivo no resume + overhead permanente
`performance/otel_flutter_ui_stall_observer.dart:82-85` usa `Timer.periodic(checkInterval=50ms)` **permanente** desde `start()` e nunca pausa no lifecycle. Dois problemas:
- **Falso positivo**: ao voltar de background, o gap entre o último tick (antes do paused) e o primeiro tick (no resume) será enorme e classificado como "stall" gigante espúrio (`recordTick`/`observedDelay`, `:95-128`). Não há gating por `AppLifecycleState`.
- **Overhead**: timer a cada 50ms acordando o isolate 20×/s continuamente em produção é overhead não-trivial em mobile (bateria/wakeups), mesmo sem stall.
Correção: pausar o timer em `paused`/`hidden` e resetar `_lastTickAt` no `resumed`; considerar intervalo maior ou desligado por default.

### A3 — Observers e handlers de erro sem try/catch (resiliência parcial)
Não há `try/catch` em torno das chamadas de tracer/meter/logger nos observers nem nos handlers de erro. A proteção é apenas o gate `Otel.isInitialized`. Pontos sensíveis:
- `onFrameTimings`/`recordFrameSample` (`frame_timing_observer.dart:123-180`) roda no callback de timings do engine — se `record`/`add` lançar, propaga para o engine.
- `recordFlutterFrameworkError`/`recordFlutterPlatformError` (`errors/otel_flutter_error_integration.dart`) substituem `FlutterError.onError` e `PlatformDispatcher.onError`. Se a própria gravação OTel lançar, o handler de erro do app quebra — efeito pior justamente no caminho de captura de crash. **Sugestão**: envolver as gravações em `try/catch` e sempre delegar ao `fallback`/`presentError` mesmo se a telemetria falhar. Ponto positivo: os listeners do usuário já são despachados com guarda de `Future` (`error_hooks.dart:64-67`), mas exceções síncronas do listener não são capturadas.

### A4 — Resource: faltam `device.*`, `service.version`, `telemetry.sdk.*`; `host.name` = PII
O resource é montado por `Resource.autoDetect` com apenas `ProcessResourceDetector` + `HostResourceDetector` (`comon_otel/lib/src/core/resource.dart:43-46`). O detector real (`platform_runtime_io.dart:13-30`) só produz:
```dart
'process.pid', 'process.executable.name', 'process.runtime.name'='dart',
'process.runtime.version', 'os.type', 'os.description', 'host.name'
```
- **Ausentes**: `device.model.identifier`, `device.manufacturer`, `os.name`/`os.version` (separados), `service.version` e **`telemetry.sdk.*`** (grep por `telemetry.sdk` no core: **nenhum resultado**). O contrato cita nominalmente `device.*`, `os.*`, `service.version`, `telemetry.sdk.*` como convenção esperada — hoje o usuário teria que fornecer tudo manualmente via `resourceAttributes`. Não há integração com `package_info`/`device_info` em nenhum pacote (grep confirmou ausência).
- **PII**: `host.name` vem de `Platform.localHostname` (`platform_runtime_io.dart:24-29`), que em iOS/Android frequentemente é o nome do dispositivo do usuário ("iPhone de João") — vaza PII no resource de todo telemetry.
Correção: adicionar um detector mobile (device_info_plus/package_info_plus) populando `device.*`, `os.name`, `os.version`, `service.version`, `deployment.environment` e `telemetry.sdk.{name,version,language}`; remover ou anonimizar `host.name` em mobile.

### A5 — Crashes nativos NÃO são capturados (limite honesto)
A captura cobre apenas o mundo Dart: `FlutterError.onError` (framework) e `PlatformDispatcher.onError` (erros não tratados do isolate raiz) — `comon_otel_flutter.dart:113-136`. Isso captura erros Dart síncronos/assíncronos do isolate principal e os converte em span `flutter.error`/`flutter.platform_error` com `recordException` + `setStatus(error)` e atributos OTel corretos (`exception.type`/`exception.message`/stacktrace via `recordException`) — ver `errors/otel_flutter_error_integration.dart:34-49,83-97`. **Não capturados**: crashes nativos (SIGSEGV/ANR no lado Android/iOS, exceções em plugins nativos, erros em isolates secundários sem zone). Para esses seria necessária integração com Crashlytics/Sentry-native ou um signal handler nativo — fora do escopo deste pacote. Reportar o limite explicitamente na doc.

### A6 — `markFirstInteraction` depende de chamada manual
`ComonOtelFlutterInstrumentation.markFirstInteraction` (`comon_otel_flutter.dart:181-183`) só emite o log `app.first_interaction` se o app chamar manualmente (como no exemplo, `main.dart:71`). Não é automático — aceitável, mas vale documentar para não dar falsa sensação de cobertura.

---

## OK / PONTOS FORTES

- **Captura de erros Dart bem feita**: usa convenção OTel correta — `exception.type`/`exception.message` via `SemanticAttributes` e `span.recordException` + `setStatus(SpanStatus.error)` (`error_integration.dart:34-49,108-115`). Preserva e delega ao handler anterior (`previousFlutterErrorHandler`/`presentError`, `error_integration.dart:51-57`) e ao `PlatformDispatcher` anterior, evitando engolir o comportamento padrão.
- **Isolamento por `Otel.isInitialized`** consistente em todos os componentes (lifecycle, navigation, startup, frame, stall, interactions) — instrumentação não explode se o SDK não foi inicializado; degrada para no-op (ex.: `interactions:67-69,100-102` chamam a ação direto sem tracing).
- **Restauração no `dispose`**: `ComonOtelFlutterInstrumentation.dispose` (`comon_otel_flutter.dart:186-204`) remove observers, restaura `FlutterError.onError`/`PlatformDispatcher.onError` anteriores, fecha spans ativos e limpa hooks/breadcrumbs. Bom higiene de ciclo de vida.
- **Frame timing** usa `addTimingsCallback` do engine (caminho oficial, `comon_otel_flutter.dart:96`) e histogramas com `boundaries` sensatas (`[8,16,32,50,100]` ms, `frame_timing_observer.dart:60`) + contadores slow/jank classificados — bom design quando exportado (depende de B1).
- **Breadcrumbs** com buffer circular limitado (`ListQueue`, capacidade default 20, `breadcrumbs.dart:7-49`) anexados aos erros como `flutter.error.breadcrumbs` (`error_integration.dart:152-159`) + contexto de rota no erro (`_applyRouteContext`, `:161-180`) — boa correlação para debugging de crash.
- **Atributos de tela** redundantes mas úteis: tanto `flutter.route.name`/`flutter.route.runtime_type` quanto `screen.name`/`screen.class` (`otel_navigator_observer.dart:106-109`), facilitando consultas no Tempo independentemente da convenção adotada.
- **Configurabilidade**: todos os nomes de span/métrica/log e thresholds são parametrizáveis via `ComonOtelFlutterConfig` e cada sinal tem flag de liga/desliga — permite ajustar para o contrato do Collector sem fork.
