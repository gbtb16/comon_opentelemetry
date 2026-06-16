# Spec — Revisão pós-implementação da Fase 1 + limpeza dos minors

> **Status:** Proposta para revisão
> **Data:** 2026-06-16
> **Autor:** Síntese pós-execução (subagent-driven-development) + review final agregado
> **Artefato revisado:** branch `fix/mobile-readiness-blockers` do fork `serezhia/comon_opentelemetry` (tip `2e0ae62`)
> **Specs/planos-fonte:** `docs/superpowers/specs/2026-06-09-comon-otel-mobile-readiness-design.md`, `docs/superpowers/plans/2026-06-15-comon-otel-mobile-blockers.md`

---

## 1. Contexto e objetivo

A Fase 1 (bloqueadores **B1–B6**) + **F2.1** (PII/resource) foi implementada na branch `fix/mobile-readiness-blockers`, task a task, cada uma com TDD + review de spec + review de qualidade. Esta spec **não** abre escopo novo de produto — ela faz duas coisas:

1. **Revisão de fechamento:** confirmar que a Fase 1 + F2.1 ficaram completas contra a design spec de 2026-06-09 e registrar explicitamente o que continua **fora de escopo** (deferido) e o que ainda precisa de **verificação empírica** (não coberta por unit test).
2. **Limpeza dos minors:** transformar em trabalho concreto os achados *Minor* levantados nos reviews por-task e no review final agregado que foram conscientemente **não corrigidos** durante a execução.

**Objetivo:** deixar a branch num estado em que o único trabalho restante antes do merge seja (a) os minors abaixo e (b) a verificação end-to-end — sem surpresas escondidas.

---

## 2. Veredito da revisão de fechamento

**A Fase 1 + F2.1 está funcionalmente completa e coerente.** O review final agregado classificou a branch como *ready-with-minors*; o único achado *Important* (exemplos de init do README não compunham) **já foi corrigido** no commit `2e0ae62`. Cobertura confirmada:

| Bloqueador | Commit | Estado |
|---|---|---|
| B1 — flush-chain poisoning | `710354b` | ✅ try/catch em BatchSpan/LogProcessor; testes de recuperação |
| B3 — knobs de batching/metric no `init` | `7ffa6d7` | ✅ params explícitos sobrepõem env |
| B5 — Dio nunca quebra o request | `0468c4a` | ✅ try/catch + `handler.next` sempre |
| B6 — sem `http.route` no client | `1d380bc` | ✅ removido; testes atualizados |
| B2 — flush no background | `67a4b06` | ✅ `forceFlush` em paused/detached/hidden + contrato do metric reader |
| B4a — sem umbrella span + sanitização | `ae3ee29` | ✅ `_activeSpans` removido; rotas → `:id` |
| B4b — `screen.name` em todo span | `929728f` | ✅ `OtelFlutterScreenSpanProcessor` |
| F2.1 — resource + PII | `dd1ea04` | ✅ `serviceVersion`/`resourceDetectors`/`TelemetrySdkResourceDetector` + helper mobile sem PII |

**Totais de teste:** core 92 · dio 13 · flutter 23 · `flutter analyze` limpo.

---

## 3. Fora de escopo (deferido — confirmar, não fazer)

Registrado para que a revisão não os confunda com "esquecimentos":

- **F2.2 — reporte de erro a nível de SDK.** B1 e B5 engolem erro silenciosamente por decisão travada. Um hook de reporte (`_reportError`) é o trabalho F2.2 — **não** está nesta spec.
- **F2.3–F2.7** e todo o **roadmap da Fase 3** — separados, fora desta spec.

---

## 4. Verificação empírica pendente (não coberta por unit test)

Unit tests são necessários mas insuficientes. Antes do go-live, validar empiricamente (origem: §Verification Plan do plano de 2026-06-15):

1. **`detectMobileResourceAttributes` em device real.** A função async é platform-channel-bound e **não tem unit test** (só a função pura `mobileResourceAttributesFrom` tem). Rodar o app de exemplo em **iOS e Android reais** e confirmar: `os.name` = `"iOS"`/`"Android"` (e **nunca** o nome do aparelho), `os.version` limpo (release no Android), `device.model.identifier`/`device.manufacturer` plausíveis, e **ausência de `host.name`**.
2. **Stitch mobile → backend** no Tempo via W3C, e que o span HTTP carrega `screen.name` (B4b), contra o demo stack (`demo/otel_end_to_end/docker-compose.yml`) e/ou staging.
3. **Contra o collector da empresa (staging):** OTLP/HTTP JSON aceito em `/otel/http` com TLS + auth; atributos com os nomes do contrato; **nenhum `http.route`** do client chega no spanmetrics (B6); **nenhum `host.name`** no resource (F2.1).
4. **Regressões da §7 da design spec:** `AlwaysOnSampler` default mantido no client; temporalidade de métrica cumulativa; logs dentro de span carregam `trace_id`/`span_id`.

> Estes itens são **gates de go-live**, não necessariamente trabalho de código — mas devem ser executados e registrados antes do merge/adoção.

---

## 5. Minors a corrigir (o trabalho concreto desta spec)

Cada item abaixo deve virar um passo TDD onde aplicável. Prioridade: **M1–M2** (cobertura de teste real) acima de **M3–M5** (cosmético/robustez).

### M1 — Testar o swallow de `onResponse`/`onError` no interceptor Dio (B5)
- **Origem:** review final, *Minor*. Hoje só o `onRequest` tem teste de throw forçado (via `spanNameBuilder`). `onResponse`/`onError` têm estrutura idêntica de try/catch mas **nenhum teste** força um throw dentro deles.
- **Fazer:** em `packages/comon_otel_dio/test/comon_otel_dio_test.dart`, dois testes que forçam a telemetria a estourar no caminho de resposta e no de erro (ex.: stub/estado que faça `_applyResponseMetadata`/`_applyHttpStatus` ou `recordException` lançar), e assertam que (a) a resposta/erro ainda propaga normalmente e (b) `handler.next` foi chamado. Se a API não expõe um seam fácil para forçar o throw nesses caminhos, documentar a limitação no teste em vez de forçar artificialmente.

### M2 — Parametrizar o teste de background-flush para os 3 estados (B2)
- **Origem:** review de qualidade da B2, *Minor*. `_isBackgrounding` cobre `paused`/`detached`/`hidden`, mas o teste só dirige `paused`.
- **Fazer:** em `packages/comon_otel_flutter/test/comon_otel_flutter_test.dart`, parametrizar (ou triplicar) o teste de flush para confirmar que `detached` e `hidden` também disparam `forceFlush`, e que estados não-background (`resumed`/`inactive`) **não** disparam.

### M3 — `telemetry.sdk.version` hardcoded pode dessincronizar do pubspec (F2.1)
- **Origem:** review de qualidade da F2.1, *Minor*. `TelemetrySdkResourceDetector` retorna `'0.0.1-alpha.1'` hardcoded; num bump de versão, diverge do `pubspec.yaml`.
- **Fazer (escolher um):** (a) comentário explícito no detector amarrando-o à versão do pacote ("manter em sincronia com pubspec"); ou (b) derivar a versão em build-time (codegen/asset) se valer o custo. Para alpha, (a) é provavelmente suficiente — decidir na revisão.

### M4 — Precedência de `service.version`: param explícito deveria vencer (F2.1)
- **Origem:** self-flag do implementer + review final, *Minor*. Em `Resource.autoDetect`/`Resource`, `service.version` do param `serviceVersion` é setado **antes** de `...?extra`, então um detector que emitisse `service.version` sobrescreveria o param explícito. Hoje **benigno** (nenhum detector shipado emite `service.version`).
- **Fazer:** decidir e tornar explícita a precedência intencional (o param explícito **deve** vencer, por intenção da spec). Mínimo: comentário documentando a precedência atual; ideal: garantir que o `serviceVersion` explícito não seja sobreposto por um detector (pequeno guard), com um teste.

### M5 — Remover `.catchError((_) {})` agora desnecessário nos testes do B1
- **Origem:** review final, *Minor*. Com o fix do B1, o primeiro `forceFlush()` nos testes de recuperação **resolve** (não rejeita mais), então o `.catchError((_) {})` virou ruído.
- **Fazer:** remover o `.catchError` dos dois testes do B1 em `packages/comon_otel/test/src/signals_pipeline_tests.dart`, confirmando que continuam verdes (a recuperação ainda é asserta pelo segundo flush + export do segundo item).

---

## 6. Notas de não-trabalho (confirmadas na revisão — sem ação)

- `spanNamePrefix`/`routeSpanNamePrefix` permanecem como **API pública inerte** (B4a removeu o umbrella span que os consumia). Docstrings já corrigidas para refletir isso. Manter como compat — **não** remover sem um ciclo de deprecação.
- Fire-and-forget do `unawaited(Otel.forceFlush())` no background (B2): limitação aceita no plano ("o único ponto confiável"); sem ação.

---

## 7. Critério de pronto

- M1–M5 implementados (M1–M2 com testes verdes; M3–M4 decididos e documentados; M5 limpo).
- Suítes seguem verdes (core/dio/flutter) + `analyze` limpo.
- §4 (verificação empírica) executada e registrada — ou explicitamente agendada como gate de go-live separado, se a revisão decidir que não bloqueia o merge da branch.
