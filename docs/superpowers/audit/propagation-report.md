# Auditoria — Propagação W3C e Instrumentação Dio

Escopo: `packages/comon_otel_dio` + `packages/comon_otel` (contexto/propagação/trace).
Objetivo: costurar trace mobile (Flutter/Dio) → backend Java Spring Boot (OTel-Java) no Grafana Tempo.

## Resumo

**Veredito: trace mobile → Spring Boot vai costurar — SIM, com ressalvas.**

O núcleo de propagação está correto: o interceptor Dio injeta `traceparent` no formato W3C exato (`00-{32hex}-{16hex}-{2hex}`), com o flag de sampling derivado da decisão real do sampler (não hardcoded), e o propagador global padrão é o composite W3C tracecontext + baggage. O OTel-Java fará o `extract` sem problema e o span do backend será filho do span do Dio. Os nomes de atributo HTTP usam a convenção nova (`http.request.method`, `http.response.status_code`) e o interceptor NÃO repete o erro do React (`company.name`/`company.id`).

As ressalvas são reais e impactam o end-to-end em produção: (1) `http.route` recebe o path cru com IDs (`/users/12345`) numa dimensão PERMITIDA do spanmetrics → explosão de cardinalidade métrica; (2) `url.full` carrega a query string completa → PII/bloat no trace storage; (3) o interceptor NÃO é resiliente a exceções — uma falha na instrumentação derruba a request real do usuário.

## BLOQUEADORES

### B1 — `http.route` recebe `uri.path` cru (IDs), explodindo cardinalidade numa dimensão PERMITIDA

`otel_dio_interceptor.dart:92`
```dart
SemanticAttributes.httpRoute: uri.path.isEmpty ? '/' : uri.path,
```
`SemanticAttributes.httpRoute` = `'http.route'` (`semantic_attributes.dart:33`), que está na lista de dimensões permitidas do spanmetrics connector. O valor injetado é o path concreto da request (ex.: `/users/12345`, `/orders/abc-987`), não um template de rota (`/users/{id}`).

**Impacto end-to-end:** como o NOME do atributo está correto, o filtro `drop_high_cardinality`/sanitize do collector NÃO o derruba — ele passa direto e cada ID vira uma série métrica nova no spanmetrics. É exatamente o caso que a "lei" de cardinalidade pune: dimensão permitida com valor de alta cardinalidade. Agravante semântico: `http.route` é atributo de SERVER; num span `SpanKind.client` o Dio não conhece o template de rota do backend, então o atributo é semanticamente incorreto além de explosivo.

**Correção concreta:** não emitir `http.route` no client. O backend Java já emite o `http.route` correto (template). No mobile, remover a linha 92. Se quiser uma dimensão estável de baixa cardinalidade no client, derive um template manual via `spanNameBuilder`/filtro, mas nunca o path cru em `http.route`.

### B2 — `onRequest`/`onResponse`/`onError` sem try/catch: instrumentação que falha quebra a request do usuário

`otel_dio_interceptor.dart:78-142` (`onRequest`)
```dart
void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
  if (!Otel.isInitialized || !(requestFilter?.call(options) ?? true)) {
    handler.next(options);
    return;
  }
  ...
  final span = Otel.instance.tracerProvider.getTracer(...).startSpan(...); // pode lançar
  ...
  Otel.propagator.inject(...);   // pode lançar
  options.headers.addAll(carrier);
  ...
  handler.next(options);         // linha 141 — só executa se nada acima lançar
}
```
Não há nenhum `try/catch` envolvendo a criação do span, o `inject` ou a captura de headers. Se qualquer chamada entre as linhas 85 e 140 lançar (ex.: sampler custom com bug, carrier malformado, header inesperado), `handler.next(options)` na linha 141 NUNCA é chamado e a request real do usuário trava/falha. A mesma estrutura sem proteção existe em `onResponse` (144-157) e `onError` (159-182): exceção na manipulação do span impede o `handler.next(response/err)`.

**Impacto end-to-end:** telemetria opcional vira ponto único de falha do app. Viola o princípio de que instrumentação nunca deve afetar o comportamento observável da aplicação.

**Correção concreta:** envolver a lógica de telemetria em `try/catch` que, em caso de erro, apenas registra/ignora e SEMPRE chama `handler.next(...)`. Padrão:
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
(e equivalente garantindo `handler.next` em `onResponse`/`onError`).

## ATENÇÃO

### A1 — `url.full` com query string completa (PII / bloat no trace storage)

`otel_dio_interceptor.dart:91`
```dart
SemanticAttributes.httpUrl: uri.toString(),
```
`SemanticAttributes.httpUrl` = `'url.full'` (`semantic_attributes.dart:36`). `uri.toString()` inclui a query string inteira (ex.: `?token=...&cpf=...&email=...`).

**Enquadramento correto:** `url.full` NÃO está na lista de dimensões permitidas do spanmetrics → o connector não agrega por ele → NÃO explode cardinalidade de métrica. O dano é outro: PII vazada e payload inflado no trace storage do Tempo. Diferente de B1 (que é cardinalidade métrica). Recomenda-se redigir/remover a query string antes de setar `url.full`, ou setar apenas `url.path`/`url.scheme`/`server.address` (já presentes nas linhas 92-95).

### A2 — Bit `random` (0x02) ligado por padrão em spans raiz mobile

`tracer_provider.dart:100-103`
```dart
final traceFlags = TraceFlags.fromSampled(
  sampled,
  random: resolvedParentContext?.traceFlags.isRandom ?? true,
);
```
Para um span raiz no mobile (sem parent remoto), `random` cai no `?? true` → o flag serializado vira `03` (sampled+random) ou `02` (não sampled+random), em vez de `01`/`00`. Isso é VÁLIDO em W3C (bit 1 = random trace-id flag) e o OTel-Java lê apenas o bit 0 (sampled) para a decisão de continuação, então o `extract` no backend funciona normalmente. Não bloqueia. Mencionado apenas para evitar confusão ao inspecionar `traceparent` no Tempo (verá `-03` e não `-01`).

### A3 — `_applyHttpStatus` deixa 4xx como `unset`

`otel_dio_interceptor.dart:232-235` — status 4xx → `SpanStatus.unset`. É uma escolha defensável (erro do cliente não é falha do servidor) e alinhada com a convenção OTel para client spans, mas note que esses spans não aparecerão como erro no Tempo. Apenas confirme que é o comportamento desejado.

## OK / PONTOS FORTES

1. **traceparent em formato W3C exato.** `w3c_trace_context_propagator.dart:22-23`
   ```dart
   carrier['traceparent'] =
       '00-${spanContext.traceId}-${spanContext.spanId}-${spanContext.traceFlags.hex}';
   ```
   `traceId` = 32 hex lowercase (`trace_id.dart:9,12`), `spanId` = 16 hex (typed), `traceFlags.hex` = 2 chars lowercase com pad (`trace_flags.dart:28`). Bate com `00-{32hex}-{16hex}-{2hex}`. O OTel-Java continua (extract) sem problema. **(Pergunta 1)**

2. **Flag de sampling derivado da decisão real do sampler, NÃO hardcoded.** `tracer_provider.dart:98-103` — `samplingResult.sampled` (decisão do `sampler.decide(...)`) alimenta `TraceFlags.fromSampled(sampled, ...)`, que vira o `traceFlags` do `SpanContext.local` (linhas 110-115), e é esse flag que o propagador serializa. Logo o backend amostra coerentemente com o mobile. **(Pergunta 2)**

3. **Propagador composto W3C corretamente montado como padrão.** `global_propagator.dart:12-14` — `defaultPropagator = CompositePropagator([W3CTraceContextPropagator(), W3CBaggagePropagator()])`. `Otel.propagator` retorna `GlobalPropagators.instance` (`otel.dart:537`). O interceptor chama `Otel.propagator.inject(...)` (`otel_dio_interceptor.dart:118-124`), então o Dio usa W3C de fato. `tracestate` é injetado quando presente (`w3c_trace_context_propagator.dart:25-28`); `baggage` é injetado pelo `W3CBaggagePropagator` a partir de `OtelContext.currentBaggage` passado no snapshot (`otel_dio_interceptor.dart:121`). **(Pergunta 3)**

4. **Nomes de atributo HTTP corretos (convenção nova), sem repetir o erro do React.** `semantic_attributes.dart`: `httpMethod = 'http.request.method'` (l.18), `httpStatusCode = 'http.response.status_code'` (l.24), `httpRoute = 'http.route'` (l.33). NÃO usa legados `http.method`/`http.status_code`. O interceptor NÃO emite `company.name`/`company.id` (erro do React) — esses atributos não aparecem em nenhum ponto do interceptor. **(Pergunta 4)** — ressalva: o VALOR de `http.route` é problemático (ver B1), mas o NOME está certo.

5. **SpanKind.client correto.** `otel_dio_interceptor.dart:107` — `kind: SpanKind.client`. Nome do span via `_defaultSpanNameBuilder` = `'HTTP {METHOD}'` (l.70-72), baixa cardinalidade (bom para spanmetrics). Captura de erro: em 5xx ou erro de transporte, `recordException` + `SpanStatus.error` (l.168-174); demais status via `_applyHttpStatus`. **(Pergunta 5)**

6. **Headers sensíveis redigidos na captura de atributos.** `_defaultSensitiveHeaders` inclui `authorization`, `cookie`, etc. (l.30-36); `_addCapturedHeaderAttributes` substitui por `[REDACTED]` (l.264-267). Reforça o `attributes/sanitize` do collector. (Nota: só afeta headers capturados como atributos; o header `authorization` continua sendo enviado na request, como esperado.)

---

### Tabela de evidência rápida

| Pergunta | Veredito | Evidência |
|---|---|---|
| 1. Injeta traceparent W3C? | SIM, formato exato | `w3c_trace_context_propagator.dart:22-23` |
| 2. Flag de sampling do sampler? | SIM, não hardcoded | `tracer_provider.dart:98-103` |
| 3. tracestate/baggage + composite W3C? | SIM | `global_propagator.dart:12-14`, `otel_dio_interceptor.dart:118-124` |
| 4. Nomes HTTP corretos? | SIM (nomes); valor de route ruim | `semantic_attributes.dart:18,24,33` / B1 |
| 5. SpanKind.client + erro? | SIM | `otel_dio_interceptor.dart:107,168-174` |
| 6. PII/cardinalidade? | PROBLEMA | B1 (`:92`), A1 (`:91`) |
| 7. Resiliente a exceções? | NÃO | B2 (`:78-142`) |
